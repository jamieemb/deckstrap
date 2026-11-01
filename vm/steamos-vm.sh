#!/usr/bin/env bash
# Steam Deck test VM on Linux: real SteamOS in QEMU/KVM. Same actions as the
# PowerShell version (see vm/README.md): setup | install | run | snapshot | restore | push | ssh | status
set -euo pipefail

ACTION="${1:-run}"; shift || true
VM_DIR="${VM_DIR:-$HOME/VMs/steamos}"
MEM="${MEM:-6144}"; CPUS="${CPUS:-4}"; DISK_GB="${DISK_GB:-80}"; SSH_PORT="${SSH_PORT:-2222}"
NAME="${NAME:-fresh}"
URL="https://steamdeck-images.steamos.cloud/recovery/steamdeck-recovery-4.img.bz2"
BZ2="$VM_DIR/steamdeck-recovery-4.img.bz2"; IMG="$VM_DIR/steamdeck-recovery-4.img"
DISK="$VM_DIR/steamos.qcow2"; VARS="$VM_DIR/efi-vars.fd"

# OVMF locations differ per distro
find_ovmf() {
  local c
  for c in /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/edk2-ovmf/x64/OVMF_CODE.fd /usr/share/qemu/edk2-x86_64-code.fd; do
    [[ -f "$c" ]] && { echo "$c"; return; }
  done
  echo "OVMF firmware not found; install ovmf / edk2-ovmf" >&2; exit 1
}
find_ovmf_vars() {
  local c
  for c in /usr/share/edk2/x64/OVMF_VARS.4m.fd /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd /usr/share/edk2-ovmf/x64/OVMF_VARS.fd /usr/share/qemu/edk2-i386-vars.fd; do
    [[ -f "$c" ]] && { echo "$c"; return; }
  done
  exit 1
}

say() { echo "[vm] $*"; }

base_args() {
  [[ -f "$VARS" ]] || cp "$(find_ovmf_vars)" "$VARS"
  local accel="tcg,thread=multi"; [[ -w /dev/kvm ]] && accel="kvm"
  local cpu="max"; [[ "$accel" == kvm ]] && cpu="host"
  echo -name SteamOS -machine q35,accel="$accel" -cpu "$cpu" -smp "$CPUS" -m "$MEM" \
    -drive "if=pflash,format=raw,readonly=on,file=$(find_ovmf)" \
    -drive "if=pflash,format=raw,file=$VARS" \
    -drive "if=none,id=nvme0,format=qcow2,file=$DISK" \
    -device nvme,drive=nvme0,serial=deck0001,bootindex=1 \
    -device qemu-xhci -device usb-tablet -device usb-kbd \
    -device virtio-vga-gl -display gtk,gl=on \
    -nic "user,model=virtio-net-pci,hostfwd=tcp::${SSH_PORT}-:22" \
    -boot menu=on
}

case "$ACTION" in
  setup)
    mkdir -p "$VM_DIR"
    command -v qemu-system-x86_64 >/dev/null || { echo "install qemu (qemu-system-x86, qemu-img) and ovmf first" >&2; exit 1; }
    [[ -f "$IMG" ]] || { [[ -f "$BZ2" ]] || curl -fL -C - --retry 5 -o "$BZ2" "$URL"; say "unpacking"; bzip2 -dk "$BZ2"; }
    [[ -f "$DISK" ]] || qemu-img create -f qcow2 "$DISK" "${DISK_GB}G"
    say "ready. Next: $0 install" ;;
  install)
    say 'In the VM choose "Re-image Steam Deck", wait, then shut it down.'
    # shellcheck disable=SC2046
    qemu-system-x86_64 $(base_args) -drive "if=none,id=rec,format=raw,file=$IMG" -device usb-storage,drive=rec,bootindex=0 ;;
  run)
    # shellcheck disable=SC2046
    qemu-system-x86_64 $(base_args) ;;
  snapshot) qemu-img snapshot -c "$NAME" "$DISK"; qemu-img snapshot -l "$DISK" ;;
  restore)  qemu-img snapshot -a "$NAME" "$DISK"; say "rolled back to $NAME" ;;
  push)     scp -P "$SSH_PORT" -o StrictHostKeyChecking=no "$1" deck@localhost:~/ ;;
  ssh)      ssh -p "$SSH_PORT" -o StrictHostKeyChecking=no deck@localhost ;;
  status)   ls -la "$VM_DIR" 2>/dev/null; [[ -f "$DISK" ]] && qemu-img snapshot -l "$DISK" ;;
  *) echo "usage: $0 setup|install|run|snapshot|restore|push <file>|ssh|status" >&2; exit 1 ;;
esac
