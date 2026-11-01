#!/usr/bin/env python3
"""deckstrap profile tool.

A profile is one JSON file describing a Steam Deck setup: which Decky plugins,
CSS Loader themes and Audio Loader packs to install fresh from their stores,
the settings to apply on top, and which other modules to run. Nothing in it is
copied code; store ids and names are enough to rebuild everything.

Commands
  export [--from DIR] [--name NAME] [--redact] [--out FILE]
      Build a profile from a Decky homebrew folder (default ~/homebrew).
  get PROFILE DOTTED.PATH [DEFAULT] [--fields a,b]
      Print a value for shell use (lists one per line, objects as JSON).
  materialize PROFILE DEST
      Write the profile's Decky settings/theme-state files into DEST, which
      mirrors the homebrew layout (settings/, themes/, sounds/).
  validate PROFILE
"""
import argparse
import json
import os
import re
import sys
from pathlib import Path

SCHEMA_VERSION = 1
SECRET_KEY_RE = re.compile(r"(api[_-]?key|token|secret|password|passwd)", re.I)

DEFAULTS = {
    "version": SCHEMA_VERSION,
    "name": "My Steam Deck",
    "home": {"restore": True},
    "system": {"ssh": True, "ssh_authorized_key": "", "hostname": "", "timezone": ""},
    "flatpaks": [
        "org.mozilla.firefox",
        "net.davidotek.pupgui2",
        "com.github.tchx84.Flatseal",
    ],
    "firefox": {
        "enabled": True,
        "default_browser": True,
        "homepage": "",
        "disable_telemetry": True,
        "extensions": [
            {"id": "uBlock0@raymondhill.net",
             "url": "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"},
        ],
    },
    "decky": {
        "enabled": True,
        "branch": "stable",
        "fresh_themes": "match",
        "plugins": [],
        "settings": {},
        "themes": [],
        "profiles": [],
        "css_store": "",
        "sounds": {"packs": [], "config": None},
    },
    "ge_proton": True,
    "cryoutilities": {"install": True, "recommended": True},
    "flatpak_auto_update": True,
    "desktop": {
        "dark_theme": False,
        "disable_screenlock": True,
        "shell_extras": True,
        "git": {"name": "", "email": ""},
    },
    "distrobox": {"container": "", "image": "docker.io/library/archlinux:latest",
                  "packages": ["git", "neovim", "htop", "ripgrep"], "export": ["nvim", "htop", "rg"]},
    "pacman": False,
    "emudeck": {"install": False, "emulation_dir": "", "bios": True},
    "os_update_check": True,
}


# ---------------------------------------------------------------------------
def read_text(p: Path) -> str:
    return p.read_text(encoding="utf-8-sig")


def read_json(p: Path):
    return json.loads(read_text(p))


def file_value(p: Path):
    """JSON files become objects; other text files strings; binaries None."""
    if p.suffix.lower() == ".json":
        try:
            return read_json(p)
        except Exception:
            pass
    try:
        return read_text(p)
    except UnicodeDecodeError:
        return None


def redact(obj, path, found):
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            if SECRET_KEY_RE.search(k) and isinstance(v, str) and v:
                out[k] = ""
                found.append(f"{path}#{k}")
            else:
                out[k] = redact(v, path, found)
        return out
    if isinstance(obj, list):
        return [redact(v, path, found) for v in obj]
    return obj


def deep_merge(base, over):
    if isinstance(base, dict) and isinstance(over, dict):
        out = dict(base)
        for k, v in over.items():
            out[k] = deep_merge(base.get(k), v) if k in base else v
        return out
    return over


# ---------------------------------------------------------------------------
def export(homebrew: Path, name: str, do_redact: bool):
    prof = json.loads(json.dumps(DEFAULTS))
    prof["name"] = name
    decky = prof["decky"]
    redacted = []

    settings_dir = homebrew / "settings"
    loader = {}
    if (settings_dir / "loader.json").is_file():
        loader = read_json(settings_dir / "loader.json")
    decky["branch"] = {0: "stable", 1: "prerelease"}.get(loader.get("branch", 0), "stable")
    decky["plugins"] = list(loader.get("pluginOrder", []))

    settings = {}
    if settings_dir.is_dir():
        for f in sorted(settings_dir.rglob("*")):
            if not f.is_file():
                continue
            rel = f.relative_to(settings_dir).as_posix()
            v = file_value(f)
            if v is None:
                continue
            if rel == "loader.json" and isinstance(v, dict):
                v = {k: x for k, x in v.items() if not k.startswith("user_info")}
            if do_redact:
                v = redact(v, "settings/" + rel, redacted)
            settings[rel] = v
    decky["settings"] = settings

    themes, profiles, local_themes = [], [], []
    themes_dir = homebrew / "themes"
    if themes_dir.is_dir():
        for d in sorted(themes_dir.iterdir()):
            if not d.is_dir():
                continue
            tj = d / "theme.json"
            theme = read_json(tj) if tj.is_file() else {}
            cfg_p = d / "config_USER.json"
            config = read_json(cfg_p) if cfg_p.is_file() else None
            if "PRESET" in theme.get("flags", []) or d.name.endswith(".profile"):
                profiles.append({"folder": d.name, "theme": theme, "config": config})
            elif theme.get("id"):
                themes.append({"name": d.name, "id": theme["id"],
                               "version": theme.get("version", ""), "config": config})
            else:
                local_themes.append(d.name)
        store = themes_dir / "STORE"
        decky["css_store"] = read_text(store) if store.is_file() else ""
    decky["themes"] = themes
    decky["profiles"] = profiles
    if local_themes:
        decky["themes_local"] = local_themes

    packs, local_packs = [], []
    sounds_dir = homebrew / "sounds"
    cfg = None
    if sounds_dir.is_dir():
        for d in sorted(sounds_dir.iterdir()):
            if not d.is_dir():
                continue
            pj = d / "pack.json"
            pack = read_json(pj) if pj.is_file() else {}
            if pack.get("id"):
                packs.append({"name": d.name, "id": pack["id"], "version": pack.get("version", "")})
            else:
                local_packs.append(d.name)
        c = sounds_dir / "config.json"
        cfg = read_json(c) if c.is_file() else None
    decky["sounds"] = {"packs": packs, "config": cfg}
    if local_packs:
        decky["sounds"]["packs_local"] = local_packs

    if redacted:
        prof["redacted"] = redacted
    return prof, local_themes, local_packs


# ---------------------------------------------------------------------------
def materialize(prof: dict, dest: Path):
    """Write settings and theme/sound state files into DEST (homebrew layout)."""
    decky = prof.get("decky", {})
    written = 0

    sdir = dest / "settings"
    for rel, v in decky.get("settings", {}).items():
        p = sdir / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        if rel == "loader.json" and p.is_file():
            try:
                v = deep_merge(read_json(p), v)   # keep user_info.* Decky wrote
            except Exception:
                pass
        if isinstance(v, str):
            p.write_text(v, encoding="utf-8", newline="\n")
        else:
            p.write_text(json.dumps(v, indent=4) + "\n", encoding="utf-8", newline="\n")
        written += 1

    tdir = dest / "themes"
    for t in decky.get("themes", []):
        if t.get("config") is not None:
            p = tdir / t["name"] / "config_USER.json"
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(json.dumps(t["config"]), encoding="utf-8", newline="\n")
            written += 1
    for pr in decky.get("profiles", []):
        d = tdir / pr["folder"]
        d.mkdir(parents=True, exist_ok=True)
        (d / "theme.json").write_text(json.dumps(pr.get("theme", {})), encoding="utf-8", newline="\n")
        if pr.get("config") is not None:
            (d / "config_USER.json").write_text(json.dumps(pr["config"]), encoding="utf-8", newline="\n")
        written += 1
    if decky.get("css_store"):
        tdir.mkdir(parents=True, exist_ok=True)
        (tdir / "STORE").write_text(decky["css_store"], encoding="utf-8", newline="\n")
        written += 1

    sounds = decky.get("sounds", {}) or {}
    if sounds.get("config") is not None:
        (dest / "sounds").mkdir(parents=True, exist_ok=True)
        (dest / "sounds" / "config.json").write_text(json.dumps(sounds["config"]), encoding="utf-8", newline="\n")
        written += 1
    return written


# ---------------------------------------------------------------------------
def validate(prof: dict) -> list:
    errs = []
    if prof.get("version") != SCHEMA_VERSION:
        errs.append(f"version must be {SCHEMA_VERSION}")
    d = prof.get("decky")
    if d is not None:
        if not isinstance(d.get("plugins", []), list) or not all(isinstance(x, str) for x in d.get("plugins", [])):
            errs.append("decky.plugins must be a list of store names")
        for t in d.get("themes", []):
            if not isinstance(t, dict) or not t.get("name") or not t.get("id"):
                errs.append(f"decky.themes entry needs name and id: {t!r}")
        for p in d.get("profiles", []):
            if not isinstance(p, dict) or not p.get("folder"):
                errs.append(f"decky.profiles entry needs folder: {p!r}")
        for p in (d.get("sounds") or {}).get("packs", []):
            if not isinstance(p, dict) or not p.get("name") or not p.get("id"):
                errs.append(f"decky.sounds.packs entry needs name and id: {p!r}")
        if not isinstance(d.get("settings", {}), dict):
            errs.append("decky.settings must be an object of relative-path -> content")
    if not isinstance(prof.get("flatpaks", []), list):
        errs.append("flatpaks must be a list")
    for e in (prof.get("firefox") or {}).get("extensions", []):
        if not isinstance(e, dict) or not e.get("id") or not e.get("url"):
            errs.append(f"firefox.extensions entry needs id and url: {e!r}")
    return errs


# ---------------------------------------------------------------------------
def lookup(prof, dotted):
    cur = prof
    for k in dotted.split("."):
        if isinstance(cur, dict) and k in cur:
            cur = cur[k]
        elif isinstance(cur, list) and k.isdigit() and int(k) < len(cur):
            cur = cur[int(k)]
        else:
            return None
    return cur


def cmd_get(args):
    prof = read_json(Path(args.profile))
    v = lookup(prof, args.path)
    if v is None:
        v = lookup(DEFAULTS, args.path)
    if v is None:
        if args.default != "":
            print(args.default)
        return
    if args.fields:
        fields = args.fields.split(",")
        for item in (v if isinstance(v, list) else []):
            if isinstance(item, dict):
                print("\t".join(str(item.get(f, "")) for f in fields))
        return
    if isinstance(v, bool):
        print("true" if v else "false")
    elif isinstance(v, (str, int, float)):
        print(v)
    elif isinstance(v, list) and all(isinstance(x, (str, int, float)) for x in v):
        for x in v:
            print(x)
    else:
        print(json.dumps(v))


def main(argv=None):
    ap = argparse.ArgumentParser(prog="profile.py", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    e = sub.add_parser("export")
    e.add_argument("--from", dest="src", default=os.path.expanduser("~/homebrew"))
    e.add_argument("--name", default="My Steam Deck")
    e.add_argument("--redact", action="store_true", help="blank values whose key looks like a secret")
    e.add_argument("--out", default="-")

    g = sub.add_parser("get")
    g.add_argument("profile"); g.add_argument("path"); g.add_argument("default", nargs="?", default="")
    g.add_argument("--fields", default="")

    m = sub.add_parser("materialize")
    m.add_argument("profile"); m.add_argument("dest")

    v = sub.add_parser("validate")
    v.add_argument("profile")

    args = ap.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(newline="\n")   # shell-friendly output on every OS

    if args.cmd == "export":
        src = Path(args.src)
        if not src.is_dir():
            print(f"no such folder: {src}", file=sys.stderr)
            return 1
        prof, local_themes, local_packs = export(src, args.name, args.redact)
        text = json.dumps(prof, indent=2, ensure_ascii=False) + "\n"
        if args.out == "-":
            sys.stdout.write(text)
        else:
            Path(args.out).write_text(text, encoding="utf-8", newline="\n")
        d = prof["decky"]
        print(f"exported: {len(d['plugins'])} plugins, {len(d['settings'])} settings files, "
              f"{len(d['themes'])} store themes, {len(d['profiles'])} profiles, "
              f"{len(d['sounds']['packs'])} sound packs", file=sys.stderr)
        for n in local_themes:
            print(f"note: theme '{n}' has no store id and cannot be installed fresh; "
                  f"put it in assets/themes/ to copy it", file=sys.stderr)
        for n in local_packs:
            print(f"note: sound pack '{n}' has no store id; put it in assets/sounds/ to copy it", file=sys.stderr)
        if prof.get("redacted"):
            print("redacted secrets (fill in after applying): " + ", ".join(prof["redacted"]), file=sys.stderr)
        return 0

    if args.cmd == "get":
        cmd_get(args)
        return 0

    if args.cmd == "materialize":
        prof = read_json(Path(args.profile))
        n = materialize(prof, Path(args.dest))
        print(n)
        return 0

    if args.cmd == "validate":
        try:
            prof = read_json(Path(args.profile))
        except Exception as ex:
            print(f"not valid JSON: {ex}", file=sys.stderr)
            return 1
        errs = validate(prof)
        for e in errs:
            print("error: " + e, file=sys.stderr)
        return 1 if errs else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
