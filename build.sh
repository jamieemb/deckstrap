#!/usr/bin/env bash
# =============================================================================
#  build.sh - pack deckstrap + a profile (+ optional assets) into ONE file
#
#      ./build.sh                                  # -> dist/deckstrap.sh (example profile, wizard on)
#      ./build.sh --profile ~/me/profile.json --assets ~/me --out /run/media/deck/USB/deckstrap.sh
#      ./build.sh --no-wizard                       # apply straight away, no module picker
#
#  The output is a self-extracting bash script: a short bootstrap, a marker
#  line, then a tar.gz of deckstrap/ (the tool), profile.json and assets/.
#  assets/ holds only these subfolders if present: bios home themes sounds downloads
#
#  On the Deck (Desktop Mode > Konsole):   bash deckstrap.sh
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="$REPO_DIR/profile.example.json"
ASSETS=""
OUT="$REPO_DIR/dist/deckstrap.sh"
WIZARD=1
MARKER="__PAYLOAD_BEGINS__"

while (($#)); do
  case "$1" in
    --profile)   PROFILE="$2"; shift 2 ;;
    --assets)    ASSETS="$2"; shift 2 ;;
    --out)       OUT="$2"; shift 2 ;;
    --no-wizard) WIZARD=0; shift ;;
    -h|--help)   sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

[[ -f "$PROFILE" ]] || { echo "profile not found: $PROFILE" >&2; exit 1; }
[[ -d "$OUT" ]] && OUT="${OUT%/}/deckstrap.sh"
mkdir -p "$(dirname "$OUT")"

# sanity: tool files are LF and parse
for f in "$REPO_DIR/deckstrap" "$REPO_DIR"/lib/*.sh "$REPO_DIR"/modules/*.sh; do
  grep -q $'\r' "$f" && { echo "$f has CRLF line endings" >&2; exit 1; }
  bash -n "$f" || { echo "syntax error in $f" >&2; exit 1; }
done
python3 "$REPO_DIR/lib/profile.py" validate "$PROFILE" || { echo "profile failed validation" >&2; exit 1; }
VERSION="$(grep -m1 'DECKSTRAP_VERSION=' "$REPO_DIR/lib/core.sh" | cut -d'"' -f2)"

# stage
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/deckstrap" "$STAGE/assets"
cp "$REPO_DIR/deckstrap" "$STAGE/deckstrap/"
cp -r "$REPO_DIR/lib" "$REPO_DIR/modules" "$STAGE/deckstrap/"
cp "$PROFILE" "$STAGE/profile.json"
ASSET_LIST=""
if [[ -n "$ASSETS" ]]; then
  [[ -d "$ASSETS" ]] || { echo "assets folder not found: $ASSETS" >&2; exit 1; }
  for sub in bios home themes sounds downloads; do
    [[ -d "$ASSETS/$sub" ]] && { cp -r "$ASSETS/$sub" "$STAGE/assets/"; ASSET_LIST+="$sub "; }
  done
fi

WIZ_FLAG=""; (( WIZARD )) && WIZ_FLAG="--wizard"
TMP="$(mktemp)"
{
  cat <<BOOT
#!/usr/bin/env bash
# deckstrap $VERSION bundle, built $(date -u +%Y-%m-%dT%H:%MZ)
# Run in Desktop Mode:   bash deckstrap.sh            (applies the bundled profile)
#                        bash deckstrap.sh --dry-run   (show what would run)
#                        bash deckstrap.sh status | list | doctor
# https://github.com/jamieemb/deckstrap
set -uo pipefail
[[ \$EUID -ne 0 ]] || { echo "Run as the normal deck user, not with sudo." >&2; exit 1; }
_line="\$(grep -a -n -m1 '^$MARKER\$' "\${BASH_SOURCE[0]}" | cut -d: -f1)"
_tmp="\$(mktemp -d "\${TMPDIR:-/tmp}/deckstrap.XXXXXX")"
trap 'rm -rf "\$_tmp"' EXIT
echo "Unpacking deckstrap $VERSION ..."
tail -n +"\$((_line + 1))" "\${BASH_SOURCE[0]}" | tar -xzf - -C "\$_tmp" || { echo "payload unpack failed" >&2; exit 1; }
_d="\$_tmp/deckstrap/deckstrap"; _p="\$_tmp/profile.json"; _a="\$_tmp/assets"
case "\${1:-}" in
  status|validate) _c="\$1"; shift; bash "\$_d" "\$_c" "\${1:-\$_p}" "\${@:2}" ;;
  list|doctor|export|version|help|-h|--help) bash "\$_d" "\$@" ;;
  *) bash "\$_d" apply "\$_p" --assets "\$_a" $WIZ_FLAG "\$@" ;;
esac
_rc=\$?
exit \$_rc
$MARKER
BOOT
  tar -C "$STAGE" -czf - deckstrap profile.json assets
} > "$TMP"

# verify
line="$(grep -a -n -m1 "^$MARKER\$" "$TMP" | cut -d: -f1)"
count="$(tail -n +"$((line + 1))" "$TMP" | tar -tzf - | wc -l)"
(( count > 0 )) || { echo "payload does not list" >&2; exit 1; }
head -n "$((line - 1))" "$TMP" | bash -n || { echo "bootstrap has a syntax error" >&2; exit 1; }

mv "$TMP" "$OUT"
chmod +x "$OUT" 2>/dev/null || true
echo "Built $OUT ($(du -h "$OUT" | cut -f1), $count files; profile: $(basename "$PROFILE"); assets: ${ASSET_LIST:-none}; wizard: $WIZARD)"
