# shellcheck shell=bash disable=SC2034
MOD_NAME="firefox"
MOD_DESC="Firefox policy: force-install extensions, homepage, telemetry, default browser (profile: firefox.*)"

mod_firefox_wanted() { pbool firefox.enabled true; }

mod_firefox_apply() { run_step "Firefox policies/extensions" _firefox_policy; }

mod_firefox_check() {
  local base; base="$(_firefox_policy_dir)" || { echo "firefox not installed"; return 1; }
  [[ -f "$base/policies/policies.json" ]] && echo "policy present" || { echo "no policy"; return 1; }
}

# Flatpak Firefox reads enterprise policies from the "systemconfig" extension
# point; the path depends on whether Firefox is a system or user flatpak.
_firefox_policy_dir() {
  flatpak_installed org.mozilla.firefox || return 1
  local arch; arch="$(flatpak --default-arch)"
  if flatpak info --system org.mozilla.firefox >/dev/null 2>&1; then
    echo "/var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/$arch/stable"
  else
    echo "$HOME/.local/share/flatpak/extension/org.mozilla.firefox.systemconfig/$arch/stable"
  fi
}

_firefox_policy() {
  local base; base="$(_firefox_policy_dir)" \
    || { err "Firefox flatpak not installed; add org.mozilla.firefox to flatpaks[]"; return 1; }
  local use_sudo=""; [[ "$base" == /var/* ]] && use_sudo="sudo"
  $use_sudo mkdir -p "$base/policies"

  local tmp; tmp="$(mktemp)"
  python3 - "$PROFILE" "$tmp" <<'PY'
import json, sys
prof = json.load(open(sys.argv[1], encoding="utf-8-sig"))
ff = prof.get("firefox", {})
pol = {
    "DontCheckDefaultBrowser": True,
    "OverrideFirstRunPage": "",
    "OverridePostUpdatePage": "",
    "ExtensionUpdate": True,
    "ExtensionSettings": {
        e["id"]: {"installation_mode": "force_installed", "install_url": e["url"]}
        for e in ff.get("extensions", [])
    },
}
if ff.get("homepage"):
    pol["Homepage"] = {"URL": ff["homepage"], "StartPage": "homepage"}
if ff.get("disable_telemetry", True):
    pol["DisableTelemetry"] = True
    pol["DisableFirefoxStudies"] = True
json.dump({"policies": pol}, open(sys.argv[2], "w", encoding="utf-8"), indent=2)
PY
  $use_sudo cp "$tmp" "$base/policies/policies.json" && $use_sudo chmod 644 "$base/policies/policies.json"
  rm -f "$tmp"
  info "wrote $base/policies/policies.json ($(pfields firefox.extensions id | wc -l) extensions)"
  if pbool firefox.default_browser true; then
    xdg-settings set default-web-browser org.mozilla.firefox.desktop 2>/dev/null \
      && info "Firefox set as default browser" || warn "could not set default browser"
  fi
}

mod_firefox_notes() {
  echo "Open Firefox once so the extensions install (about:policies lists them), then sign in to them."
}
