# shellcheck shell=bash
# deckstrap core library: logging, step runner, profile access, store helpers.
# Sourced by the deckstrap entrypoint; DECKSTRAP_DIR is set by it.

# shellcheck disable=SC2034  # used by the entrypoint and build.sh
DECKSTRAP_VERSION="0.1.1"
PROFILE_PY="$DECKSTRAP_DIR/lib/profile.py"
USER="${USER:-$(id -un)}"
export USER

# ---------------------------------------------------------------------------
#  Output
# ---------------------------------------------------------------------------
C_INFO=$'\033[1;34m'; C_OK=$'\033[1;32m'; C_WARN=$'\033[1;33m'; C_ERR=$'\033[1;31m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
info() { echo "${C_INFO}[INFO]${C_RST} $*"; }
ok()   { echo "${C_OK}[ OK ]${C_RST} $*"; }
warn() { echo "${C_WARN}[WARN]${C_RST} $*"; }
err()  { echo "${C_ERR}[FAIL]${C_RST} $*" >&2; }
die()  { err "$*"; exit 1; }

FAILED_STEPS=(); DONE_STEPS=(); SKIPPED_STEPS=()
run_step() {   # run_step "<label>" <function> [args...]
  local name="$1"; shift
  echo
  info "===== $name ====="
  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    echo "${C_DIM}  (dry run) would run: $*${C_RST}"
    SKIPPED_STEPS+=("$name"); return 0
  fi
  if "$@"; then ok "$name"; DONE_STEPS+=("$name")
  else err "$name"; FAILED_STEPS+=("$name"); return 1; fi
}

list_has() {   # list_has "a,b,c" "b"
  local IFS=','; local x
  for x in $1; do [[ "$x" == "$2" ]] && return 0; done
  return 1
}

# ---------------------------------------------------------------------------
#  Profile access (python does the JSON; python3 ships with SteamOS)
# ---------------------------------------------------------------------------
# pget <dotted.path> [default]  -> scalar as text, list of scalars one per line,
#                                  anything else as JSON. Missing -> default.
pget()  { python3 "$PROFILE_PY" get "$PROFILE" "$1" "${2:-}"; }
# pfields <dotted.path> <f1,f2> -> tab-separated fields of each object in a list
pfields() { python3 "$PROFILE_PY" get "$PROFILE" "$1" --fields "$2"; }
# pbool <dotted.path> [default]  -> exit 0 when the value is true
pbool() { [[ "$(pget "$1" "${2:-false}")" == "true" ]]; }

# ---------------------------------------------------------------------------
#  Modules
# ---------------------------------------------------------------------------
MODULES=(); declare -A MOD_DESCS=()
load_modules() {
  MODULES=(); MOD_DESCS=()
  local f
  for f in "$DECKSTRAP_DIR"/modules/*.sh; do
    MOD_NAME=""; MOD_DESC=""
    # shellcheck source=/dev/null
    source "$f"
    [[ -n "$MOD_NAME" ]] || { warn "module $f sets no MOD_NAME; ignored"; continue; }
    MODULES+=("$MOD_NAME")
    # shellcheck disable=SC2034  # read by the entrypoint's usage/wizard
    MOD_DESCS["$MOD_NAME"]="$MOD_DESC"
  done
}

# ---------------------------------------------------------------------------
#  Preflight: sudo password, cached sudo, keep-alive, cleanup
# ---------------------------------------------------------------------------
SUDO_KEEPALIVE=""
cleanup() {
  [[ -n "$SUDO_KEEPALIVE" ]] && kill "$SUDO_KEEPALIVE" 2>/dev/null
  return 0
}
preflight() {
  [[ $EUID -ne 0 ]] || die "Run deckstrap as the normal 'deck' user, not with sudo."
  grep -qi steamos /etc/os-release 2>/dev/null || warn "This does not look like SteamOS. Continuing anyway."
  command -v python3 >/dev/null || die "python3 is required."
  curl -fsSL --max-time 10 https://github.com >/dev/null || die "No internet connection (cannot reach github.com)."
  if [[ "${DECKSTRAP_GUI:-0}" == 1 ]]; then
    # the GUI backend has already set/verified the password and provides it
    # through SUDO_ASKPASS; there is no terminal to prompt on
    info "Caching sudo credentials (GUI)..."
    sudo -A -v || die "sudo failed (askpass)."
  else
    if passwd -S "$USER" 2>/dev/null | awk '{print $2}' | grep -q '^NP'; then
      warn "No sudo password is set yet. Choose one now (you will be asked twice)."
      passwd || die "Could not set password."
    fi
    info "Caching sudo credentials..."
    sudo -v || die "sudo failed."
  fi
  ( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
  SUDO_KEEPALIVE=$!
  trap cleanup EXIT
}

# ---------------------------------------------------------------------------
#  Small helpers
# ---------------------------------------------------------------------------
unzip_py() {   # unzip_py <zip> <dest-dir>   (no dependency on the unzip binary)
  python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$1" "$2"
}
json_set_default() {   # json_set_default <file> <key> <value>  (adds key if missing)
  python3 -c '
import json, sys
p, k, v = sys.argv[1:4]
d = json.load(open(p, encoding="utf-8-sig"))
if k not in d:
    d[k] = v
    json.dump(d, open(p, "w", encoding="utf-8"), indent=2)
' "$@"
}
flatpak_installed() { flatpak info "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
#  Store helpers
# ---------------------------------------------------------------------------
# Decky plugin store: JSON per plugin with versions[]; each version's "hash" is
# the sha256 of the zip on the Decky CDN. The zip unpacks to one folder
# (e.g. "CSS Loader" -> SDH-CssLoader), which is what settings/<folder> uses.
decky_store_lookup() {   # prints "<store-name>\t<hash>" for the newest version
  curl -fsSL --get --data-urlencode "query=$1" "https://plugins.deckbrew.xyz/plugins" \
  | python3 -c '
import json, sys
want = sys.argv[1].lower()
for p in json.load(sys.stdin):
    if p.get("name", "").lower() == want and p.get("versions"):
        print(p["name"] + "\t" + p["versions"][0]["hash"]); break
' "$1"
}

decky_plugin_install() {   # decky_plugin_install <store-name> <plugins-dir>; prints folder name
  local name="$1" pdir="$2" line hash tmp folder
  line="$(decky_store_lookup "$name")" || true
  [[ -n "$line" ]] || { err "not found in Decky store: '$name'"; return 1; }
  hash="${line#*$'\t'}"
  tmp="$(mktemp -d)"
  if curl -fsSL -o "$tmp/p.zip" "https://cdn.tzatzikiweeb.moe/file/steam-deck-homebrew/versions/$hash.zip" \
     && echo "$hash  $tmp/p.zip" | sha256sum -c --quiet - \
     && unzip_py "$tmp/p.zip" "$tmp/x" \
     && folder="$(basename "$(find "$tmp/x" -mindepth 1 -maxdepth 1 -type d | head -n1)")" \
     && [[ -n "$folder" && -f "$tmp/x/$folder/plugin.json" ]]; then
    # Decky's loader (root) locks ~/homebrew/plugins to mode 555 as soon as it
    # starts, so placing a plugin needs sudo; afterwards match the loader's
    # own ownership and permissions.
    if sudo rm -rf "${pdir:?}/$folder" \
       && sudo mv "$tmp/x/$folder" "$pdir/$folder" \
       && sudo chown -R "$USER:$USER" "$pdir/$folder" \
       && sudo chmod -R 555 "$pdir/$folder"; then
      rm -rf "$tmp"
      echo "$folder"
      return 0
    fi
    rm -rf "$tmp"
    err "could not place '$name' into $pdir"
    return 1
  fi
  rm -rf "$tmp"
  err "failed to download/verify '$name'"
  return 1
}

# deckthemes store (CSS Loader themes and Audio Loader packs): the API gives
# the zip blob id for a theme id; the zip unpacks to one folder.
deckthemes_install() {   # deckthemes_install <id> <folder-name> <dest-dir>
  local id="$1" name="$2" dst="$3" tmp blob top
  blob="$(curl -fsSL "https://api.deckthemes.com/themes/$id" \
          | python3 -c 'import json, sys; print(json.load(sys.stdin)["download"]["id"])' 2>/dev/null)"
  [[ -n "$blob" ]] || return 1
  tmp="$(mktemp -d)"
  if ! { curl -fsSL -o "$tmp/t.zip" "https://api.deckthemes.com/blobs/$blob" && unzip_py "$tmp/t.zip" "$tmp/x"; }; then
    rm -rf "$tmp"; return 1
  fi
  top="$(find "$tmp/x" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  [[ -n "$top" ]] || { rm -rf "$tmp"; return 1; }
  rm -rf "${dst:?}/$name"
  mv "$top" "$dst/$name"
  rm -rf "$tmp"
}
