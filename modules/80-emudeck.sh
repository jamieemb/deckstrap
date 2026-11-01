# shellcheck shell=bash disable=SC2034
MOD_NAME="emudeck"
MOD_DESC="EmuDeck installer (GUI) and BIOS files from assets/bios into Emulation/bios (profile: emudeck.*)"

mod_emudeck_wanted() { pbool emudeck.install || { pbool emudeck.bios true && [[ -d "$ASSETS/bios" ]]; }; }

mod_emudeck_apply() {
  pbool emudeck.install && run_step "EmuDeck" _emudeck_install
  if pbool emudeck.bios true && [[ -d "$ASSETS/bios" ]]; then run_step "Emulator BIOS files" _emudeck_bios; fi
  return 0
}

mod_emudeck_check() {
  local e; e="$(_emudeck_dir)" && echo "Emulation at $e" || { echo "no Emulation folder"; return 1; }
}

_emudeck_dir() {
  local d; d="$(pget emudeck.emulation_dir)"
  [[ -n "$d" && -d "$d" ]] && { echo "$d"; return 0; }
  [[ -d "$HOME/Emulation" ]] && { echo "$HOME/Emulation"; return 0; }
  for d in /run/media/deck/*/Emulation /run/media/mmcblk0p1/Emulation; do
    [[ -d "$d" ]] && { echo "$d"; return 0; }
  done
  return 1
}

_emudeck_install() {
  if [[ -d "$HOME/emudeck" ]]; then info "EmuDeck already present; skipping"; return 0; fi
  info "launching the EmuDeck installer; follow its GUI, then come back here."
  curl -fsSL https://raw.githubusercontent.com/dragoonDorise/EmuDeck/main/install.sh | bash
}

_emudeck_bios() {
  local emu; emu="$(_emudeck_dir)" || { warn "no Emulation folder yet; install EmuDeck first, then re-run"; return 1; }
  mkdir -p "$emu/bios"
  rsync -a "$ASSETS/bios/" "$emu/bios/" || return 1
  info "BIOS files copied to $emu/bios"
}
