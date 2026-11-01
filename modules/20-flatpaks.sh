# shellcheck shell=bash disable=SC2034
MOD_NAME="flatpaks"
MOD_DESC="Install Flatpak apps from Flathub (profile: flatpaks[])"

mod_flatpaks_wanted() { [[ -n "$(pget flatpaks)" ]]; }

mod_flatpaks_apply() { run_step "Flatpak apps" _flatpaks_install; }

mod_flatpaks_check() {
  local app missing=0 total=0
  while read -r app; do
    [[ -n "$app" ]] || continue
    total=$((total + 1)); flatpak_installed "$app" || missing=$((missing + 1))
  done < <(pget flatpaks)
  echo "$((total - missing))/$total installed"
  (( missing == 0 ))
}

_flatpaks_install() {
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo \
    || sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo \
    || return 1
  local app rc=0
  while read -r app; do
    [[ -n "$app" ]] || continue
    if flatpak_installed "$app"; then info "already installed: $app"; continue; fi
    info "installing $app ..."
    if ! flatpak install -y --noninteractive flathub "$app"; then
      warn "system install failed for $app, trying --user"
      flatpak install -y --noninteractive --user flathub "$app" || { err "could not install $app"; rc=1; }
    fi
  done < <(pget flatpaks)
  info "updating all flatpaks..."
  flatpak update -y --noninteractive || true
  return $rc
}
