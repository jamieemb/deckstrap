# shellcheck shell=bash disable=SC2034
MOD_NAME="ge_proton"
MOD_DESC="Latest GE-Proton into Steam's compatibilitytools.d (profile: ge_proton)"

mod_ge_proton_wanted() { pbool ge_proton true; }
mod_ge_proton_apply()  { run_step "GE-Proton" _ge_proton_install; }
mod_ge_proton_check()  {
  local d="$HOME/.steam/root/compatibilitytools.d"
  ls -d "$d"/GE-Proton* >/dev/null 2>&1 && echo "$(ls -d "$d"/GE-Proton* | xargs -n1 basename | sort -V | tail -1)" || { echo "none"; return 1; }
}
mod_ge_proton_notes()  { echo "Steam > Settings > Compatibility: pick GE-Proton for games that need it."; }

_ge_proton_install() {
  local dir="$HOME/.steam/root/compatibilitytools.d"
  mkdir -p "$dir"
  local json; json="$(curl -fsSL https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest)" || return 1
  local tag; tag="$(echo "$json" | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')"
  [[ -n "$tag" ]] || { err "could not determine latest GE-Proton tag"; return 1; }
  [[ -d "$dir/$tag" ]] && { info "$tag already installed"; return 0; }
  local tar_url sha_url tmp
  tar_url="$(echo "$json" | grep -oE 'https://[^"]+\.tar\.gz' | head -n1)"
  sha_url="$(echo "$json" | grep -oE 'https://[^"]+\.sha512sum' | head -n1)"
  tmp="$(mktemp -d)"
  info "downloading $tag ..."
  curl -fL --progress-bar -o "$tmp/ge.tar.gz" "$tar_url" || { rm -rf "$tmp"; return 1; }
  if [[ -n "$sha_url" ]]; then
    curl -fsSL -o "$tmp/ge.sha512sum" "$sha_url" \
      && (cd "$tmp" && sed "s|[^ ]*\.tar\.gz|ge.tar.gz|" ge.sha512sum | sha512sum -c -) \
      || { err "checksum failed"; rm -rf "$tmp"; return 1; }
  fi
  tar -xzf "$tmp/ge.tar.gz" -C "$dir" || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
  info "$tag installed"
}
