# shellcheck shell=bash disable=SC2034
MOD_NAME="cryoutilities"
MOD_DESC="CryoUtilities install and recommended swap/memory settings (profile: cryoutilities.*)"

mod_cryoutilities_wanted() { pbool cryoutilities.install true; }
mod_cryoutilities_apply()  { run_step "CryoUtilities" _cryo_install; }
mod_cryoutilities_check()  { [[ -x "$HOME/.cryo_utilities/cryo_utilities" ]] && echo "installed" || { echo "missing"; return 1; }; }

_cryo_install() {
  local bin="$HOME/.cryo_utilities/cryo_utilities"
  if [[ ! -x "$bin" ]]; then
    # Their install.sh pops zenity dialogs (desktop shortcut, "installed"), which
    # sit hidden behind the installer window, so fetch the release binary
    # directly and verify it against the md5 they publish alongside it.
    info "installing CryoUtilities (release binary, md5 verified)..."
    local base="https://github.com/CryoByte33/steam-deck-utilities/releases/download/latest" tmp
    tmp="$(mktemp -d)"
    if curl -fsSL -o "$tmp/cryo_utilities" "$base/cryo_utilities" \
       && curl -fsSL -o "$tmp/cu.md5" "$base/cu.md5" \
       && (cd "$tmp" && md5sum -c --quiet cu.md5); then
      mkdir -p "$HOME/.cryo_utilities"
      mv "$tmp/cryo_utilities" "$bin" && chmod +x "$bin"
      curl -fsSL -o "$HOME/.cryo_utilities/cryo-utilities.png" \
        https://raw.githubusercontent.com/CryoByte33/steam-deck-utilities/main/cmd/cryoutilities/Icon.png 2>/dev/null || true
      # same launcher their installer creates, so the GUI can be opened later from Desktop Mode
      printf '#!/usr/bin/env bash\nexport HOME="%s"\nsudo -E "%s"\n' "$HOME" "$bin" > "$HOME/.cryo_utilities/launcher.sh"
      chmod +x "$HOME/.cryo_utilities/launcher.sh"
      mkdir -p "$HOME/Desktop"
      printf '[Desktop Entry]\nName=CryoUtilities\nExec=%s\nIcon=%s\nTerminal=true\nType=Application\n' \
        "$HOME/.cryo_utilities/launcher.sh" "$HOME/.cryo_utilities/cryo-utilities.png" > "$HOME/Desktop/cryoutilities.desktop"
      chmod +x "$HOME/Desktop/cryoutilities.desktop"
    else
      rm -rf "$tmp"; err "could not download/verify CryoUtilities"; return 1
    fi
    rm -rf "$tmp"
  fi
  [[ -x "$bin" ]] || { err "CryoUtilities binary not found at $bin"; return 1; }
  if pbool cryoutilities.recommended true; then
    info "applying recommended settings (swap, swappiness, HugePages...); this resizes the swap file and can take a few minutes"
    # CryoUtilities resolves its folder from $HOME (os.UserHomeDir) and logs
    # only to ~/.cryo_utilities/cryoutilities.log. Plain sudo sets HOME=/root
    # (it then panics) and --preserve-env is refused by some sudoers policies,
    # so set HOME explicitly via env. On failure, surface its own log.
    mkdir -p "$HOME/.cryo_utilities"
    if ! sudo env HOME="$HOME" "$bin" recommended; then
      err "CryoUtilities 'recommended' exited with an error; its log says:"
      tail -n 15 "$HOME/.cryo_utilities/cryoutilities.log" 2>/dev/null | sed 's/^/    /'
      return 1
    fi
    info "CryoUtilities log tail:"; tail -n 4 "$HOME/.cryo_utilities/cryoutilities.log" 2>/dev/null | sed 's/^/    /'
  fi
}
