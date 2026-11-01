# shellcheck shell=bash disable=SC2034
MOD_NAME="flatpak_auto_update"
MOD_DESC="Daily 'flatpak update' via a systemd user timer (profile: flatpak_auto_update)"

mod_flatpak_auto_update_wanted() { pbool flatpak_auto_update true; }
mod_flatpak_auto_update_apply()  { run_step "Flatpak auto-update timer" _flatpak_timer; }
mod_flatpak_auto_update_check()  { systemctl --user is-enabled --quiet flatpak-update.timer 2>/dev/null && echo "enabled" || { echo "not enabled"; return 1; }; }

_flatpak_timer() {
  local d="$HOME/.config/systemd/user"
  mkdir -p "$d"
  cat > "$d/flatpak-update.service" <<'UNIT'
[Unit]
Description=Update Flatpak apps
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/flatpak update -y --noninteractive
UNIT
  cat > "$d/flatpak-update.timer" <<'UNIT'
[Unit]
Description=Daily Flatpak update

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
UNIT
  systemctl --user daemon-reload
  systemctl --user enable --now flatpak-update.timer
}
