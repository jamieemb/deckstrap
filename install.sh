#!/usr/bin/env bash
# One-line install, for people who prefer a terminal to the download button:
#
#   curl -fsSL https://raw.githubusercontent.com/jamieemb/deckstrap/main/install.sh | bash
#
# Downloads the latest release bundle and runs it with the module picker.
# Extra arguments are passed through, e.g.:  ... | bash -s -- --dry-run
set -euo pipefail
REPO="${DECKSTRAP_REPO:-jamieemb/deckstrap}"
URL="https://github.com/$REPO/releases/latest/download/deckstrap.sh"
f="$(mktemp "${TMPDIR:-/tmp}/deckstrap.XXXXXX.sh")"
echo "Downloading $URL ..."
curl -fL --progress-bar -o "$f" "$URL"
bash "$f" "$@"
rc=$?
rm -f "$f"
exit $rc
