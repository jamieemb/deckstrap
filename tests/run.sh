#!/usr/bin/env bash
# deckstrap test suite: syntax, shellcheck (if present), profile tool, dry-run apply, bundle build.
# Runs on Linux CI or Git Bash (needs python3 on PATH; set PYTHON to override).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
fail=0
pass() { echo "  ok   $*"; }
bad()  { echo "  FAIL $*"; fail=1; }

echo "== syntax"
for f in deckstrap build.sh install.sh tests/run.sh lib/*.sh modules/*.sh; do
  grep -q $'\r' "$f" && bad "$f has CRLF"
  bash -n "$f" && pass "$f" || bad "$f"
done

echo "== shellcheck"
if command -v shellcheck >/dev/null; then
  # warnings and errors fail the build; info/style (e.g. SC2015 for "a && ok || fail" reporting) do not
  shellcheck -x -s bash -S warning deckstrap build.sh install.sh tests/run.sh lib/*.sh modules/*.sh && pass "clean" || bad "shellcheck"
else
  echo "  skip (shellcheck not installed)"
fi

echo "== profile tool"
T="$(mktemp -d)"
FIX="$ROOT/tests/fixtures/homebrew"
python3 lib/profile.py export --from "$FIX" --name "Fixture Deck" --out "$T/profile.json" 2>"$T/export.err" && pass "export" || bad "export: $(cat "$T/export.err")"
python3 lib/profile.py validate "$T/profile.json" && pass "validate" || bad "validate"
python3 lib/profile.py validate profile.example.json && pass "validate example" || bad "validate example"

plugins="$(python3 lib/profile.py get "$T/profile.json" decky.plugins | tr '\n' ',')"
[[ "$plugins" == "CSS Loader,Bluetooth," ]] && pass "plugins from loader.json: $plugins" || bad "plugins: $plugins"
[[ "$(python3 lib/profile.py get "$T/profile.json" decky.branch)" == "stable" ]] && pass "branch" || bad "branch"
[[ "$(python3 lib/profile.py get "$T/profile.json" nope.missing dflt)" == "dflt" ]] && pass "default value" || bad "default value"
[[ "$(python3 lib/profile.py get "$T/profile.json" ge_proton)" == "true" ]] && pass "bool true" || bad "bool"
themes="$(python3 lib/profile.py get "$T/profile.json" decky.themes --fields name,id)"
[[ "$themes" == $'Centered Home\t865407ae-fb14-4db7-b123-61f6995ed757' ]] && pass "themes with ids" || bad "themes: $themes"
[[ "$(python3 lib/profile.py get "$T/profile.json" decky.profiles --fields folder)" == "Clean.profile" ]] && pass "profile detected" || bad "profiles"
[[ "$(python3 lib/profile.py get "$T/profile.json" decky.themes_local)" == "Local Theme" ]] && pass "local theme flagged" || bad "local theme"
[[ "$(python3 lib/profile.py get "$T/profile.json" decky.sounds.packs --fields name,id)" == $'Pack\t12b04b34-00c1-4600-8e71-eb0a77f47962' ]] && pass "sound pack" || bad "sound pack"
grep -q 'user_info' "$T/profile.json" && bad "user_info leaked into profile" || pass "user_info stripped"

python3 lib/profile.py export --from "$FIX" --redact --out "$T/redacted.json" >/dev/null 2>&1
grep -q '"api_key": ""' "$T/redacted.json" && pass "redact api_key" || bad "redact"

# materialize over a fake fresh homebrew (loader.json with user_info present)
mkdir -p "$T/hb/settings"; echo '{"user_info.user_name": "deck", "branch": 0}' > "$T/hb/settings/loader.json"
n="$(python3 lib/profile.py materialize "$T/profile.json" "$T/hb")" && pass "materialize wrote $n files" || bad "materialize"
[[ -f "$T/hb/settings/SDH-AnimationChanger/config.json" ]] && pass "plugin settings file" || bad "plugin settings file"
[[ "$(cat "$T/hb/settings/EmuDecky/scid.txt")" == "12345" ]] && pass "text settings file" || bad "text settings"
grep -q 'user_info.user_name' "$T/hb/settings/loader.json" && grep -q 'pluginOrder' "$T/hb/settings/loader.json" && pass "loader.json merged" || bad "loader.json merge"
[[ "$(cat "$T/hb/themes/Centered Home/config_USER.json")" == '{"active": true, "Hide Header": "No"}' ]] && pass "theme state" || bad "theme state: $(cat "$T/hb/themes/Centered Home/config_USER.json")"
[[ -f "$T/hb/themes/Clean.profile/theme.json" && -f "$T/hb/themes/Clean.profile/config_USER.json" ]] && pass "profile folder" || bad "profile folder"
[[ "$(cat "$T/hb/themes/STORE")" == $'unpinnedThemes:[]\nenableNavPatch:true' ]] && pass "STORE prefs" || bad "STORE"
[[ -f "$T/hb/sounds/config.json" ]] && pass "sounds config" || bad "sounds config"

echo "== cli"
grep -q '^deckstrap ' <<<"$(bash ./deckstrap version)" && pass "version" || bad "version"
grep -q 'decky' <<<"$(bash ./deckstrap list)" && pass "list shows modules" || bad "list"
bash ./deckstrap validate "$T/profile.json" >/dev/null && pass "validate cmd" || bad "validate cmd"
HOME="$T/home" bash ./deckstrap apply "$T/profile.json" --dry-run > "$T/dry.out" 2>&1 && pass "dry-run apply exits 0" || bad "dry-run apply: $(tail -5 "$T/dry.out")"
grep -q 'DRY RUN' "$T/dry.out" && grep -q 'Decky plugins (fresh)' "$T/dry.out" && pass "dry-run lists decky steps" || bad "dry-run output"
grep -q 'not enabled in profile' "$T/dry.out" && pass "disabled modules reported" || bad "disabled modules"
HOME="$T/home" bash ./deckstrap apply "$T/profile.json" --dry-run --only firefox > "$T/only.out" 2>&1
grep -q 'Firefox policies' "$T/only.out" && ! grep -q 'Decky plugins' "$T/only.out" && pass "--only filters" || bad "--only"

echo "== modules command"
grep -q $'^decky\tyes\t' <<<"$(bash ./deckstrap modules "$T/profile.json")" && pass "modules lists decky as wanted" || bad "modules"

echo "== gui backend"
mkdir -p "$T/assets/bios"; echo bios > "$T/assets/bios/x.bin"
HOME="$T/home3" python3 lib/server.py --profile "$T/profile.json" --assets "$T/assets" > "$T/srv.out" 2>&1 &
SRV=$!
for _ in $(seq 1 50); do grep -q '^URL=' "$T/srv.out" 2>/dev/null && break; sleep 0.2; done
url="$(sed -n 's/^URL=//p' "$T/srv.out" | head -n1)"; tok="${url##*t=}"; base="${url%%\?*}"
[[ -n "$url" ]] && pass "backend started at $base" || bad "backend start: $(cat "$T/srv.out")"
auth=(-H "X-Deckstrap-Token: $tok")
curl -fs "${auth[@]}" "${base}api/state" > "$T/state.json" && pass "state" || bad "state"
grep -q '"name": "decky"' "$T/state.json" && pass "state lists decky module" || bad "state modules: $(head -c 300 "$T/state.json")"
grep -q '"plugins": 2' "$T/state.json" && pass "state has profile summary" || bad "profile summary"
[[ "$(curl -s -o /dev/null -w '%{http_code}' "${base}api/state")" == "403" ]] && pass "token required" || bad "token not enforced"
curl -fs "${base}index.html" | grep -q '<title>deckstrap' && pass "serves ui" || bad "ui not served"
curl -fs "${auth[@]}" -H 'Content-Type: application/json' -d '{"only":["firefox","decky","emudeck"],"dry_run":true}' "${base}api/start" | grep -q '"ok": true' && pass "start dry-run" || bad "start"
for _ in $(seq 1 150); do
  curl -fs "${auth[@]}" "${base}api/state" > "$T/state.json"
  grep -q '"running": false' "$T/state.json" && grep -q '"finished": [0-9]' "$T/state.json" && break
  sleep 0.3
done
grep -q '"name": "Decky plugins (fresh)", "status": "skipped"' "$T/state.json" && pass "steps parsed from the run" || bad "steps: $(grep -o '"steps": \[[^]]*\]' "$T/state.json" | head -c 400)"
grep -q '"name": "Emulator BIOS files"' "$T/state.json" && pass "assets reached the run" || bad "assets"
grep -q 'Open Firefox once' "$T/state.json" && pass "notes collected" || bad "notes: $(grep -o '"notes": \[[^]]*\]' "$T/state.json")"
curl -fs "${auth[@]}" -X POST "${base}api/quit" >/dev/null && pass "quit" || bad "quit"
wait "$SRV" 2>/dev/null

echo "== bundle"
bash ./build.sh --profile "$T/profile.json" --assets "$T/assets" --out "$T/bundle.sh" --mode apply > "$T/build.out" 2>&1 && pass "build" || bad "build: $(cat "$T/build.out")"
grep -q '^deckstrap ' <<<"$(bash "$T/bundle.sh" version 2>/dev/null)" && pass "bundle runs tool" || bad "bundle version"
grep -q '^MODULE' <<<"$(bash "$T/bundle.sh" status 2>/dev/null)" && pass "bundle status" || bad "bundle status"
HOME="$T/home2" bash "$T/bundle.sh" --dry-run > "$T/bundle.out" 2>&1 && grep -q 'Emulator BIOS' "$T/bundle.out" && pass "bundle dry-run sees assets" || bad "bundle dry-run: $(tail -5 "$T/bundle.out")"
pl="$(grep -a -n -m1 '^__PAYLOAD_BEGINS__$' "$T/bundle.sh" | cut -d: -f1)"
tail -n +"$((pl + 1))" "$T/bundle.sh" | tar -tzf - > "$T/bundle.list" 2>/dev/null
grep -q 'ui/index.html' "$T/bundle.list" && pass "bundle carries the ui" || bad "ui missing from bundle"
shopt -s nullglob; leftovers=(/tmp/deckstrap.* "${TMPDIR:-/tmp}"/deckstrap.*); shopt -u nullglob
(( ${#leftovers[@]} )) && bad "bundle left temp dirs: ${leftovers[*]}" || pass "bundle cleans up"

rm -rf "$T"
echo
if (( fail )); then echo "TESTS FAILED"; exit 1; else echo "ALL TESTS PASSED"; fi
