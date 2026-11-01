# shellcheck shell=bash disable=SC2034
MOD_NAME="system"
MOD_DESC="Hostname, timezone, SSH (profile: system.*)"

mod_system_wanted() {
  pbool system.ssh || [[ -n "$(pget system.hostname)" || -n "$(pget system.timezone)" ]]
}

mod_system_apply() {
  local h t
  h="$(pget system.hostname)"; t="$(pget system.timezone)"
  [[ -n "$h" ]] && run_step "Hostname: $h" _system_hostname "$h"
  [[ -n "$t" ]] && run_step "Timezone: $t" _system_timezone "$t"
  pbool system.ssh && run_step "SSH" _system_ssh
  return 0
}

mod_system_check() {
  systemctl is-active --quiet sshd && echo "ssh active, host $(hostname)" || echo "ssh inactive, host $(hostname)"
}

_system_hostname() {
  [[ "$(hostname)" == "$1" ]] && { info "already $1"; return 0; }
  sudo hostnamectl set-hostname "$1"
}

_system_timezone() {
  [[ "$(timedatectl show -p Timezone --value 2>/dev/null)" == "$1" ]] && { info "already $1"; return 0; }
  sudo timedatectl set-timezone "$1" && sudo timedatectl set-ntp true
}

_system_ssh() {
  sudo systemctl enable --now sshd || return 1
  local key; key="$(pget system.ssh_authorized_key)"
  if [[ -n "$key" ]]; then
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    touch "$HOME/.ssh/authorized_keys" && chmod 600 "$HOME/.ssh/authorized_keys"
    grep -qxF "$key" "$HOME/.ssh/authorized_keys" || echo "$key" >> "$HOME/.ssh/authorized_keys"
    info "authorized_keys updated"
  fi
  local ip
  ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -n1)"
  info "SSH: ssh $USER@${ip:-<deck-ip>}"
}
