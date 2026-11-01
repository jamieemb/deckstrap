#!/usr/bin/env bash
# deckstrap launcher: fetched by the .desktop files on the website.
#   curl -fsSL https://jamieemb.github.io/deckstrap/launch.sh | bash -s -- [--profile-url URL] [app args...]
# Downloads the deckstrap desktop app (an AppImage built by CI), keeps it in
# ~/Applications, and starts it. If the app cannot run, falls back to the
# terminal installer from the site bundle.
set -uo pipefail
APP_URL="https://github.com/jamieemb/deckstrap/releases/download/ui-latest/deckstrap-ui.AppImage"
BUNDLE_URL="https://jamieemb.github.io/deckstrap/deckstrap.sh"
APP="$HOME/Applications/deckstrap-ui.AppImage"
mkdir -p "$HOME/Applications"

have_gui() { [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] && command -v zenity >/dev/null; }

download() {   # download <url> <dest> <label>
  local url="$1" dest="$2" label="$3" tmp="$2.part" pid
  curl -fL -s -o "$tmp" "$url" &
  pid=$!
  if have_gui; then
    ( while kill -0 "$pid" 2>/dev/null; do echo "# $label"; sleep 1; done ) \
      | zenity --progress --pulsate --auto-close --no-cancel --width=460 --title="deckstrap" --text="$label" >/dev/null 2>&1
  fi
  wait "$pid" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$dest"
}

# Always refresh the app: it is the latest CI build, and a stale copy is the
# usual cause of "it did that last time too".
if ! download "$APP_URL" "$APP" "Downloading the deckstrap installer (about 100 MB)..."; then
  if have_gui; then zenity --error --width=400 --text="deckstrap: could not download the installer. Check the internet connection and try again."; fi
  echo "download failed: $APP_URL" >&2
  exit 1
fi
chmod +x "$APP"

# Electron AppImages need FUSE2 to mount themselves; SteamOS has it, but fall
# back to extract-and-run just in case.
if "$APP" "$@"; then
  exit 0
elif "$APP" --appimage-extract-and-run "$@"; then
  exit 0
fi

echo "the desktop app could not start; falling back to the terminal installer" >&2
if download "$BUNDLE_URL" "$HOME/Applications/deckstrap.sh" "Downloading the fallback installer..."; then
  if command -v konsole >/dev/null && have_gui; then
    konsole --noclose -e bash "$HOME/Applications/deckstrap.sh" wizard "$@"
  else
    bash "$HOME/Applications/deckstrap.sh" wizard "$@"
  fi
fi
