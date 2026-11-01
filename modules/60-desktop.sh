# shellcheck shell=bash disable=SC2034
MOD_NAME="desktop"
MOD_DESC="Desktop Mode: dark theme, screen lock off, shell aliases, git identity (profile: desktop.*)"

mod_desktop_wanted() {
  pbool desktop.dark_theme || pbool desktop.disable_screenlock true || pbool desktop.shell_extras true \
    || [[ -n "$(pget desktop.git.name)" ]]
}

mod_desktop_apply() {
  pbool desktop.dark_theme            && run_step "KDE dark theme"      _desktop_dark
  pbool desktop.disable_screenlock true && run_step "KDE screen lock off" _desktop_screenlock
  pbool desktop.shell_extras true     && run_step "Shell aliases"       _desktop_shell_extras
  [[ -n "$(pget desktop.git.name)" ]] && run_step "Git identity"        _desktop_git
  return 0
}

_desktop_dark() {
  command -v lookandfeeltool >/dev/null || { warn "lookandfeeltool not found"; return 1; }
  lookandfeeltool -a org.kde.breezedark.desktop
}

_desktop_screenlock() {
  local kw; kw="$(command -v kwriteconfig6 || command -v kwriteconfig5)" || { warn "kwriteconfig not found"; return 1; }
  "$kw" --file kscreenlockerrc --group Daemon --key Autolock false
  "$kw" --file kscreenlockerrc --group Daemon --key LockOnResume false
  info "screen lock disabled (takes effect after the next Desktop Mode login)"
}

_desktop_shell_extras() {
  local rc="$HOME/.bashrc" start="# >>> deckstrap extras >>>" end="# <<< deckstrap extras <<<"
  touch "$rc"
  grep -qF "$start" "$rc" && sed -i "/^$start\$/,/^$end\$/d" "$rc"
  cat >> "$rc" <<EXTRAS
$start
export PATH="\$HOME/.local/bin:\$PATH"
alias ll='ls -lah --color=auto'
alias gamemode='qdbus org.kde.Shutdown /Shutdown logout'   # back to Gaming Mode
alias fpu='flatpak update -y'
alias decky-log='journalctl -u plugin_loader -f'
alias decky-restart='sudo systemctl restart plugin_loader'
alias osupdate='steamos-update check && steamos-update'
$end
EXTRAS
  info "aliases added to ~/.bashrc (open a new terminal to use them)"
}

_desktop_git() {
  command -v git >/dev/null || { warn "git not on PATH (use the distrobox module)"; return 1; }
  git config --global user.name "$(pget desktop.git.name)"
  git config --global user.email "$(pget desktop.git.email)"
  git config --global init.defaultBranch main
}
