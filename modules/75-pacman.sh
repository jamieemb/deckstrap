# shellcheck shell=bash disable=SC2034
MOD_NAME="pacman"
MOD_DESC="Make the rootfs writable and init pacman keys. WIPED by every SteamOS update (profile: pacman)"

mod_pacman_wanted() { pbool pacman; }
mod_pacman_apply()  { run_step "pacman (rootfs writable)" _pacman_enable; }

_pacman_enable() {
  warn "Making the rootfs writable. Anything installed with pacman is lost on the next SteamOS update."
  sudo steamos-readonly disable || return 1
  sudo pacman-key --init && sudo pacman-key --populate archlinux holo || return 1
  sudo pacman -Sy || return 1
  info "pacman ready. Example: sudo pacman -S --needed base-devel"
}
