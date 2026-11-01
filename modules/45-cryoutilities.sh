# shellcheck shell=bash disable=SC2034
MOD_NAME="cryoutilities"
MOD_DESC="CryoUtilities install and recommended swap/memory settings (profile: cryoutilities.*)"

mod_cryoutilities_wanted() { pbool cryoutilities.install true; }
mod_cryoutilities_apply()  { run_step "CryoUtilities" _cryo_install; }
mod_cryoutilities_check()  { [[ -x "$HOME/.cryo_utilities/cryo_utilities" ]] && echo "installed" || { echo "missing"; return 1; }; }

_cryo_install() {
  local bin="$HOME/.cryo_utilities/cryo_utilities"
  if [[ ! -x "$bin" ]]; then
    info "installing CryoUtilities..."
    curl -fsSL https://raw.githubusercontent.com/CryoByte33/steam-deck-utilities/main/install.sh | bash -s -- || return 1
  fi
  [[ -x "$bin" ]] || { err "CryoUtilities binary not found at $bin"; return 1; }
  if pbool cryoutilities.recommended true; then
    info "applying recommended settings (swap, swappiness, HugePages...)"
    sudo "$bin" recommended || return 1
  fi
}
