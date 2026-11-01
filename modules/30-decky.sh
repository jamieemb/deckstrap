# shellcheck shell=bash disable=SC2034
MOD_NAME="decky"
MOD_DESC="Decky Loader + plugins, CSS themes and sound packs fresh from their stores, with saved settings applied"

mod_decky_wanted() { pbool decky.enabled true; }

mod_decky_apply() {
  local before=${#FAILED_STEPS[@]}
  run_step "Decky Loader"            _decky_loader || return 1
  run_step "Decky plugins (fresh)"   _decky_plugins
  run_step "Decky settings + state"  _decky_settings
  run_step "CSS Loader themes"       _decky_themes
  run_step "Audio Loader packs"      _decky_sounds
  run_step "Restart Decky"           _decky_restart
  (( ${#FAILED_STEPS[@]} == before ))
}

mod_decky_check() {
  systemctl is-active --quiet plugin_loader || { echo "loader not running"; return 1; }
  local want have=0 missing=()
  while read -r want; do
    [[ -n "$want" ]] || continue
    # settings/<folder> is keyed by the zip folder, so count plugin.json names instead
    if grep -lsq "\"name\": *\"$want\"" "$HOME"/homebrew/plugins/*/plugin.json 2>/dev/null; then have=$((have + 1)); else missing+=("$want"); fi
  done < <(pget decky.plugins)
  echo "loader running, $have plugins present${missing:+, missing: ${missing[*]}}"
  (( ${#missing[@]} == 0 ))
}

mod_decky_notes() {
  echo "Return to Gaming Mode and open the Decky (...) menu: plugins, themes and sounds were installed fresh with your saved settings."
}

# ---------------------------------------------------------------------------
_decky_loader() {
  mkdir -p "$HOME/.steam/steam" && touch "$HOME/.steam/steam/.cef-enable-remote-debugging"
  if systemctl is-active --quiet plugin_loader && [[ -d "$HOME/homebrew/services" ]]; then
    info "Decky Loader already installed and running; skipping installer."
  else
    local branch; branch="$(pget decky.branch stable)"
    local script="install_release.sh"; [[ "$branch" == "prerelease" ]] && script="install_prerelease.sh"
    info "running the official Decky installer ($branch)..."
    curl -fsSL "https://github.com/SteamDeckHomebrew/decky-installer/releases/latest/download/$script" | sh || return 1
  fi
  mkdir -p "$HOME/homebrew/plugins" "$HOME/homebrew/settings" "$HOME/homebrew/themes" "$HOME/homebrew/sounds"
  sudo chown -R "$USER:$USER" "$HOME/homebrew"
}

_decky_plugins() {
  local pdir="$HOME/homebrew/plugins" name folder rc=0 n=0
  mapfile -t names < <(pget decky.plugins)
  (( ${#names[@]} )) || { warn "decky.plugins is empty; nothing to install"; return 0; }
  info "installing ${#names[@]} plugins fresh from the store: ${names[*]}"
  for name in "${names[@]}"; do
    if folder="$(decky_plugin_install "$name" "$pdir")"; then
      info "  fresh: $name  ->  plugins/$folder"; n=$((n + 1))
    else
      rc=1
    fi
  done
  info "$n/${#names[@]} plugins installed"
  return $rc
}

# Writes settings/<plugin>/..., loader.json (plugin order), each theme's
# config_USER.json, CSS Loader profiles, STORE prefs and sounds/config.json
# from the profile into ~/homebrew. Theme and pack folders are fetched next.
_decky_settings() {
  # The loader (root) owns settings/loader.json and other files it has
  # written, so build the tree in a staging dir and copy it in with sudo.
  local stage n; stage="$(mktemp -d)"
  mkdir -p "$stage/settings"
  [[ -f "$HOME/homebrew/settings/loader.json" ]] && cp "$HOME/homebrew/settings/loader.json" "$stage/settings/" 2>/dev/null
  n="$(python3 "$PROFILE_PY" materialize "$PROFILE" "$stage")" || { rm -rf "$stage"; return 1; }
  sudo rsync -a "$stage/" "$HOME/homebrew/" || { rm -rf "$stage"; return 1; }
  sudo chown -R "$USER:$USER" "$HOME/homebrew/settings" "$HOME/homebrew/themes" "$HOME/homebrew/sounds" 2>/dev/null || true
  rm -rf "$stage"
  info "wrote $n settings/state files from the profile"
}

_decky_themes() {
  local dst="$HOME/homebrew/themes" name id fresh=0 copied=0 rc=0
  mkdir -p "$dst"
  while IFS=$'\t' read -r name id; do
    [[ -n "$name" ]] || continue
    local cfg="$dst/$name/config_USER.json" keep=""
    [[ -f "$cfg" ]] && keep="$(cat "$cfg")"
    if pbool decky.fresh_themes true && deckthemes_install "$id" "$name" "$dst"; then
      json_set_default "$dst/$name/theme.json" id "$id" 2>/dev/null || true   # lets CSS Loader offer updates
      fresh=$((fresh + 1)); info "  fresh: $name"
    elif [[ -d "$ASSETS/themes/$name" ]]; then
      rm -rf "${dst:?}/$name"; cp -a "$ASSETS/themes/$name" "$dst/$name"
      copied=$((copied + 1)); info "  copied from assets: $name"
    else
      err "  could not fetch '$name' ($id) and no copy in assets/themes"; rc=1; continue
    fi
    [[ -n "$keep" ]] && printf '%s' "$keep" > "$cfg"   # re-apply saved state over the fresh folder
  done < <(pfields decky.themes name,id)
  # local-only themes (no store id) can only come from assets
  local t
  while read -r t; do
    [[ -n "$t" ]] || continue
    if [[ -d "$ASSETS/themes/$t" ]]; then rm -rf "${dst:?}/$t"; cp -a "$ASSETS/themes/$t" "$dst/$t"; copied=$((copied + 1)); info "  copied local theme: $t"
    else warn "  local theme '$t' not in assets/themes; skipped"; fi
  done < <(pget decky.themes_local)
  info "themes: $fresh fresh from store, $copied copied, $(pfields decky.profiles folder | wc -l) profiles written"
  return $rc
}

_decky_sounds() {
  local dst="$HOME/homebrew/sounds" name id fresh=0 copied=0 rc=0
  mkdir -p "$dst"
  while IFS=$'\t' read -r name id; do
    [[ -n "$name" ]] || continue
    if pbool decky.fresh_themes true && deckthemes_install "$id" "$name" "$dst"; then
      json_set_default "$dst/$name/pack.json" id "$id" 2>/dev/null || true
      fresh=$((fresh + 1)); info "  fresh: $name"
    elif [[ -d "$ASSETS/sounds/$name" ]]; then
      rm -rf "${dst:?}/$name"; cp -a "$ASSETS/sounds/$name" "$dst/$name"
      copied=$((copied + 1)); info "  copied from assets: $name"
    else
      err "  could not fetch pack '$name' ($id)"; rc=1
    fi
  done < <(pfields decky.sounds.packs name,id)
  info "sound packs: $fresh fresh from store, $copied copied"
  return $rc
}

_decky_restart() {
  sudo chown -R "$USER:$USER" "$HOME/homebrew"
  sudo systemctl restart plugin_loader || { warn "plugin_loader restart failed; a reboot will do the same."; return 1; }
  info "Decky restarted."
}
