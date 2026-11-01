#!/usr/bin/env bash
# =============================================================================
#  pack-profile.sh - make a shareable profile pack (.tar.gz)
#
#      ./pack-profile.sh --profile ~/deck-backup/profile.json --assets ~/deck-backup --out docs/profiles/my-deck.tar.gz
#
#  A pack holds profile.json plus assets/themes and assets/sounds (the exact
#  backed-up theme and sound-pack folders the "match" policy falls back to).
#  --with-home adds assets/home, --with-bios adds assets/bios; both are off by
#  default because home holds personal files and BIOS images are copyrighted.
#  The assets folder may be a deck-backup checkout (homebrew/themes layout).
#
#  Use it with:  bash deckstrap.sh --profile-url https://.../my-deck.tar.gz
#  or paste the URL into the installer's "Use a different profile" box.
# =============================================================================
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE=""; ASSETS=""; OUT=""; WITH_HOME=0; WITH_BIOS=0
while (($#)); do
  case "$1" in
    --profile)   PROFILE="$2"; shift 2 ;;
    --assets)    ASSETS="$2"; shift 2 ;;
    --out)       OUT="$2"; shift 2 ;;
    --with-home) WITH_HOME=1; shift ;;
    --with-bios) WITH_BIOS=1; shift ;;
    -h|--help)   sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done
[[ -f "$PROFILE" ]] || { echo "--profile <profile.json> is required" >&2; exit 1; }
[[ -n "$OUT" ]] || { echo "--out <file.tar.gz> is required" >&2; exit 1; }
python3 "$REPO_DIR/lib/profile.py" validate "$PROFILE"

STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/assets"
cp "$PROFILE" "$STAGE/profile.json"
list=""
if [[ -n "$ASSETS" ]]; then
  subs=(themes sounds); (( WITH_HOME )) && subs+=(home); (( WITH_BIOS )) && subs+=(bios)
  for sub in "${subs[@]}"; do
    src="$ASSETS/$sub"; [[ -d "$src" ]] || src="$ASSETS/homebrew/$sub"
    [[ -d "$src" ]] && { cp -r "$src" "$STAGE/assets/$sub"; list+="$sub "; }
  done
  rm -f "$STAGE/assets/themes/css_translations.json"
fi
mkdir -p "$(dirname "$OUT")"
tar -C "$STAGE" -czf - profile.json assets > "$OUT"   # via stdout: a "C:" in the path would otherwise look like a remote host to tar
echo "Packed $OUT ($(du -h "$OUT" | cut -f1); profile: $(basename "$PROFILE"); assets: ${list:-none})"
