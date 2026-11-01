#!/usr/bin/env python3
"""deckstrap GUI backend.

A tiny local HTTP server (stdlib only, python3 ships with SteamOS) that serves
the web UI from ../ui and exposes a small JSON API the UI uses to:

  * read the profile summary and module list      GET  /api/state
  * set or verify the sudo password               POST /api/sudo   {password, mode: "verify"|"set"}
  * start `deckstrap apply` for chosen modules    POST /api/start  {only: [...], dry_run: bool}
  * follow progress and the log                   GET  /api/state?since=N
  * return to Gaming Mode / close the installer   POST /api/gamemode, POST /api/quit

Binds to 127.0.0.1 only, on a random port. Every API call must carry the
random token the server prints at start (the UI gets it from the page URL),
so other local pages cannot drive the installer.

The sudo password never touches disk: it is passed to the apply process in
its environment, and a SUDO_ASKPASS helper echoes it to sudo, which uses the
helper automatically because the process has no terminal.

Usage:  server.py --profile P [--assets DIR] [--port 0] [--no-browser-token]
Prints one line on start:  URL=http://127.0.0.1:PORT/?t=TOKEN
"""
import argparse
import json
import os
import re
import secrets
import select
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
UI_DIR = ROOT / "ui"
DECKSTRAP = ROOT / "deckstrap"
BASH = shutil.which("bash") or "bash"   # resolved explicitly so dev hosts with several bash binaries pick the one on PATH
ANSI = re.compile(r"\x1b\[[0-9;]*m")
NO_SUDO = False   # --insecure-no-sudo: skip password handling (UI development only)

STEP_START = re.compile(r"^\[INFO\] ===== (.+) =====$")
STEP_OK = re.compile(r"^\[ OK \] (.+)$")
STEP_FAIL = re.compile(r"^\[FAIL\] (.+)$")
STEP_DRY = re.compile(r"^\s+\(dry run\)")
NOT_ENABLED = re.compile(r"^-- (\S+): not enabled")


class State:
    def __init__(self, profile: Path, assets: Path):
        self.lock = threading.Lock()
        self.sudo_pw = None
        self.sudo_verified = False
        self.quit_event = threading.Event()
        self.source = ""
        self.use_profile(profile, assets)

    def use_profile(self, profile: Path, assets: Path):
        self.profile = profile
        self.assets = assets
        self.prof = json.loads(profile.read_text(encoding="utf-8-sig"))
        self.modules = self._load_modules()
        self.reset_run()

    def load_profile_source(self, url: str):
        """Fetch a profile.json or a .tar.gz profile pack from a URL (http(s)/file) and switch to it."""
        if not re.match(r"^(https?|file)://", url):
            return False, "enter an http(s) URL"
        dest = Path(tempfile.mkdtemp(prefix="deckstrap-profile."))
        src = dest / "source.bin"
        try:
            with urllib.request.urlopen(url, timeout=60) as r, open(src, "wb") as f:
                f.write(r.read())
        except Exception as ex:   # noqa: BLE001
            return False, f"download failed: {ex}"
        try:
            json.loads(src.read_text(encoding="utf-8-sig"))
            (dest / "profile.json").write_bytes(src.read_bytes())
        except Exception:
            try:
                with tarfile.open(src, "r:gz") as t:
                    for m in t.getmembers():
                        if m.name.startswith("/") or ".." in Path(m.name).parts:
                            return False, "pack contains unsafe paths"
                    t.extractall(dest)
            except Exception as ex:   # noqa: BLE001
                return False, f"not a profile.json or .tar.gz pack: {ex}"
            if not (dest / "profile.json").is_file():
                return False, "pack has no profile.json at its root"
        chk = subprocess.run([sys.executable, str(HERE / "profile.py"), "validate", str(dest / "profile.json")],
                             capture_output=True, text=True)
        if chk.returncode != 0:
            return False, "profile failed validation: " + chk.stderr.strip()[:200]
        assets = dest / "assets" if (dest / "assets").is_dir() else dest
        with self.lock:
            if self.run["running"]:
                return False, "an install is running"
            self.use_profile(dest / "profile.json", assets)
            self.source = url
        return True, ""

    def reset_run(self):
        self.run = {
            "running": False,
            "started": None,
            "finished": None,
            "exit": None,
            "steps": [],        # [{name, status: running|ok|fail|skipped}]
            "notes": [],
            "summary": "",
        }
        self.log = []

    def _load_modules(self):
        out = subprocess.run(
            [BASH, str(DECKSTRAP), "modules", str(self.profile)],
            capture_output=True, text=True, env={**os.environ, "ASSETS": str(self.assets)},
        )
        mods = []
        for line in out.stdout.splitlines():
            parts = line.split("\t")
            if len(parts) == 3:
                mods.append({"name": parts[0], "wanted": parts[1] == "yes", "desc": parts[2]})
        return mods

    # ---- sudo ---------------------------------------------------------------
    @staticmethod
    def password_is_set():
        try:
            out = subprocess.run(["passwd", "-S", os.environ.get("USER", "deck")],
                                 capture_output=True, text=True, timeout=5).stdout.split()
            return len(out) > 1 and not out[1].startswith("NP")
        except Exception:
            return True   # assume set; verify will tell

    @staticmethod
    def verify_password(pw: str) -> bool:
        try:
            r = subprocess.run(["sudo", "-S", "-k", "-v"], input=pw + "\n",
                               capture_output=True, text=True, timeout=20)
            return r.returncode == 0
        except Exception:
            return False

    @staticmethod
    def set_password(pw: str):
        """Run `passwd` for the current user under a pty (it refuses plain stdin)."""
        import pty   # Linux only; imported here so the server also runs on CI/dev hosts
        pid, fd = pty.fork()
        if pid == 0:
            os.execvp("passwd", ["passwd"])
        buf = b""
        sent = 0
        deadline = time.time() + 30
        try:
            while time.time() < deadline:
                r, _, _ = select.select([fd], [], [], 0.5)
                if r:
                    try:
                        chunk = os.read(fd, 1024)
                    except OSError:
                        break
                    if not chunk:
                        break
                    buf += chunk
                    low = buf.lower()
                    if b"password" in low and low.count(b"password") > sent:
                        os.write(fd, (pw + "\n").encode())
                        sent += 1
                        if sent >= 3:
                            pass
            _, status = os.waitpid(pid, 0)
        finally:
            os.close(fd)
        ok = os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0
        msg = ANSI.sub("", buf.decode(errors="replace"))
        return ok, msg.strip().splitlines()[-1] if msg.strip() else ""

    # ---- run ---------------------------------------------------------------
    def start(self, only, dry_run):
        with self.lock:
            if self.run["running"]:
                return False, "already running"
            self.reset_run()
            self.run["running"] = True
            self.run["started"] = time.time()
        threading.Thread(target=self._runner, args=(only, dry_run), daemon=True).start()
        return True, ""

    def _runner(self, only, dry_run):
        env = dict(os.environ)
        env["DECKSTRAP_GUI"] = "1"
        tmpdir = None
        if self.sudo_pw is not None and not NO_SUDO:
            tmpdir = tempfile.mkdtemp(prefix="deckstrap-ask.")
            os.chmod(tmpdir, 0o700)
            helper = Path(tmpdir) / "askpass.sh"
            helper.write_text('#!/bin/sh\nprintf "%s\\n" "$DECKSTRAP_SUDO_PW"\n', encoding="utf-8")
            helper.chmod(stat.S_IRWXU)
            env["SUDO_ASKPASS"] = str(helper)
            env["DECKSTRAP_SUDO_PW"] = self.sudo_pw
        cmd = [BASH, str(DECKSTRAP), "apply", str(self.profile), "--assets", str(self.assets)]
        if only:
            cmd += ["--only", ",".join(only)]
        if dry_run:
            cmd.append("--dry-run")
        try:
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    stdin=subprocess.DEVNULL, text=True, env=env, bufsize=1)
            in_notes = False
            for raw in proc.stdout:
                line = ANSI.sub("", raw.rstrip("\n"))
                with self.lock:
                    self.log.append(line)
                    self._parse(line, in_notes)
                    if line.startswith("Next, by hand:"):
                        in_notes = True
                    elif in_notes and line.startswith("  * "):
                        self.run["notes"].append(line[4:])
                    elif in_notes and line.startswith("===="):
                        in_notes = False
            proc.wait()
            with self.lock:
                self.run["exit"] = proc.returncode
        except Exception as ex:   # noqa: BLE001
            with self.lock:
                self.log.append(f"[FAIL] could not run deckstrap: {ex}")
                self.run["exit"] = 1
        finally:
            with self.lock:
                self.run["running"] = False
                self.run["finished"] = time.time()
                for s in self.run["steps"]:
                    if s["status"] == "running":
                        s["status"] = "fail"
                ok = sum(1 for s in self.run["steps"] if s["status"] == "ok")
                bad = sum(1 for s in self.run["steps"] if s["status"] == "fail")
                sk = sum(1 for s in self.run["steps"] if s["status"] == "skipped")
                self.run["summary"] = f"{ok} done, {bad} failed, {sk} skipped"
            if tmpdir:
                try:
                    (Path(tmpdir) / "askpass.sh").unlink()
                    os.rmdir(tmpdir)
                except OSError:
                    pass

    def _parse(self, line, in_notes):
        m = STEP_START.match(line)
        if m:
            self.run["steps"].append({"name": m.group(1), "status": "running"})
            return
        for rx, status in ((STEP_OK, "ok"), (STEP_FAIL, "fail")):
            m = rx.match(line)
            if m:
                name = m.group(1)
                for s in reversed(self.run["steps"]):
                    if s["name"] == name and s["status"] == "running":
                        s["status"] = status
                        return
                return
        if STEP_DRY.match(line) and self.run["steps"]:
            self.run["steps"][-1]["status"] = "skipped"

    def snapshot(self, since):
        with self.lock:
            return {
                "profile": {
                    "name": self.prof.get("name", "profile"),
                    "plugins": len(self.prof.get("decky", {}).get("plugins", [])),
                    "themes": len(self.prof.get("decky", {}).get("themes", [])),
                    "flatpaks": len(self.prof.get("flatpaks", [])),
                    "source": self.source,
                },
                "modules": self.modules,
                "sudo": {"password_set": self.password_is_set(), "verified": self.sudo_verified},
                "run": self.run,
                "log": self.log[since:],
                "log_next": len(self.log),
            }


def make_handler(state: State, token: str):
    class Handler(SimpleHTTPRequestHandler):
        def __init__(self, *a, **kw):
            super().__init__(*a, directory=str(UI_DIR), **kw)

        def log_message(self, *_):   # quiet
            pass

        def _json(self, code, obj):
            body = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def _auth(self):
            if self.headers.get("X-Deckstrap-Token") == token:
                return True
            self._json(403, {"error": "bad token"})
            return False

        def _body(self):
            n = int(self.headers.get("Content-Length") or 0)
            return json.loads(self.rfile.read(n) or b"{}")

        def do_GET(self):
            u = urlparse(self.path)
            if u.path == "/api/state":
                if not self._auth():
                    return
                since = int(parse_qs(u.query).get("since", ["0"])[0])
                return self._json(200, state.snapshot(since))
            if u.path == "/":
                self.path = "/index.html"
            return super().do_GET()

        def do_POST(self):
            u = urlparse(self.path)
            if not self._auth():
                return
            if u.path == "/api/sudo":
                b = self._body()
                pw, mode = b.get("password", ""), b.get("mode", "verify")
                if not pw:
                    return self._json(400, {"ok": False, "error": "empty password"})
                if NO_SUDO:
                    state.sudo_pw, state.sudo_verified = pw, True
                    return self._json(200, {"ok": True})
                if mode == "set":
                    ok, msg = state.set_password(pw)
                    if not ok:
                        return self._json(200, {"ok": False, "error": msg or "passwd failed"})
                if state.verify_password(pw):
                    state.sudo_pw, state.sudo_verified = pw, True
                    return self._json(200, {"ok": True})
                return self._json(200, {"ok": False, "error": "sudo did not accept that password"})
            if u.path == "/api/start":
                b = self._body()
                ok, err = state.start(b.get("only") or [], bool(b.get("dry_run")))
                return self._json(200 if ok else 409, {"ok": ok, "error": err})
            if u.path == "/api/profile":
                ok, err = state.load_profile_source(self._body().get("url", "").strip())
                return self._json(200, {"ok": ok, "error": err})
            if u.path == "/api/gamemode":
                subprocess.Popen(["qdbus", "org.kde.Shutdown", "/Shutdown", "logout"])
                return self._json(200, {"ok": True})
            if u.path == "/api/quit":
                self._json(200, {"ok": True})
                state.quit_event.set()
                return
            return self._json(404, {"error": "no such endpoint"})

    return Handler


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--profile", required=True)
    ap.add_argument("--assets", default="")
    ap.add_argument("--port", type=int, default=0)
    ap.add_argument("--insecure-no-sudo", action="store_true",
                    help="accept any password and run apply without askpass (UI development on a dev host only)")
    args = ap.parse_args()
    global NO_SUDO
    NO_SUDO = args.insecure_no_sudo
    profile = Path(args.profile).resolve()
    assets = Path(args.assets).resolve() if args.assets else profile.parent
    state = State(profile, assets)
    token = secrets.token_urlsafe(16)
    srv = ThreadingHTTPServer(("127.0.0.1", args.port), make_handler(state, token))
    port = srv.server_address[1]
    print(f"URL=http://127.0.0.1:{port}/?t={token}", flush=True)
    t = threading.Thread(target=srv.serve_forever, daemon=True)
    t.start()
    try:
        while not state.quit_event.wait(0.5):
            pass
    except KeyboardInterrupt:
        pass
    srv.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
