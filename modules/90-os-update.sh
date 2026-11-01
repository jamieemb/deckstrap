# shellcheck shell=bash disable=SC2034
MOD_NAME="os_update_check"
MOD_DESC="Report whether a SteamOS update is pending; changes nothing (profile: os_update_check)"

mod_os_update_check_wanted() { pbool os_update_check true; }
mod_os_update_check_apply()  { run_step "SteamOS update check" _os_update_check; }

_os_update_check() {
  command -v steamos-update >/dev/null || return 0
  if sudo steamos-update check >/dev/null 2>&1; then
    warn "A SteamOS update is available. Install it from Gaming Mode > Settings > System,"
    warn "then run deckstrap again (Decky needs reinstalling after major updates)."
  else
    info "SteamOS is up to date."
  fi
  return 0
}
