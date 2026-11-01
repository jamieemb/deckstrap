# shellcheck shell=bash disable=SC2034
MOD_NAME="home"
MOD_DESC="Restore dotfiles/config from assets/home over \$HOME"

mod_home_wanted() { pbool home.restore true && [[ -d "$ASSETS/home" ]]; }

mod_home_apply() { run_step "Restore home/dotfiles" _home_restore; }

_home_restore() {
  sudo rsync -a --exclude 'homebrew' "$ASSETS/home/" "$HOME/" || return 1
  sudo chown -R "$USER:$USER" "$HOME"
  if [[ -d "$HOME/.ssh" ]]; then
    chmod 700 "$HOME/.ssh"
    chmod 600 "$HOME"/.ssh/* 2>/dev/null || true
  fi
  return 0
}
