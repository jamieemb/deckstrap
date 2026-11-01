# shellcheck shell=bash disable=SC2034
MOD_NAME="distrobox"
MOD_DESC="Persistent Arch container for CLI tools, exported to ~/.local/bin (profile: distrobox.*)"

mod_distrobox_wanted() { [[ -n "$(pget distrobox.container)" ]]; }
mod_distrobox_apply()  { run_step "Distrobox container" _distrobox_setup; }
mod_distrobox_check()  {
  local c; c="$(pget distrobox.container)"
  distrobox list 2>/dev/null | grep -q "| $c " && echo "container '$c' exists" || { echo "no container"; return 1; }
}

_distrobox_setup() {
  command -v distrobox >/dev/null || { err "distrobox not found (needs SteamOS 3.5+)"; return 1; }
  local c image; c="$(pget distrobox.container)"; image="$(pget distrobox.image docker.io/library/archlinux:latest)"
  if ! distrobox list 2>/dev/null | grep -q "| $c "; then
    info "creating container '$c' from $image ..."
    distrobox create -Y -n "$c" -i "$image" || return 1
  fi
  local pkgs=(); mapfile -t pkgs < <(pget distrobox.packages)
  if (( ${#pkgs[@]} )); then
    info "installing packages: ${pkgs[*]}"
    distrobox enter "$c" -- sudo pacman -Syu --noconfirm --needed "${pkgs[@]}" || return 1
  fi
  local bin path
  while read -r bin; do
    [[ -n "$bin" ]] || continue
    path="$(distrobox enter "$c" -- which "$bin" 2>/dev/null)" || { warn "  $bin not found in container"; continue; }
    distrobox enter "$c" -- distrobox-export --bin "$path" --export-path "$HOME/.local/bin" \
      && info "  exported $bin -> ~/.local/bin/$bin" || warn "  could not export $bin"
  done < <(pget distrobox.export)
  return 0
}
