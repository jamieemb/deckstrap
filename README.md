# deckstrap

Set up a Steam Deck from a profile. One file, one click, fresh every time.

deckstrap installs Decky Loader, its plugins, CSS Loader themes and Audio
Loader packs **fresh from their stores**, then applies the settings recorded in
a profile: plugin order and options, which themes are enabled and how they are
patched, your sound pack, Firefox extensions, and a set of optional modules
(GE-Proton, CryoUtilities, SSH, Distrobox, EmuDeck BIOS files and more).
Nothing from an old install is copied as code. A profile is a single JSON
file of names, store ids and settings, so it is small, readable and shareable.

**Users:** go to the website, download the installer, double-click it in
Desktop Mode. See [docs/index.html](docs/index.html).

**Rebuilding your own Deck:** export a profile once, build a bundle that
carries it, keep the bundle on a USB stick.

## Commands

```
deckstrap apply profile.json [--only a,b] [--skip a,b] [--dry-run] [--wizard] [--assets DIR]
deckstrap export [--from ~/homebrew] [--name NAME] [--redact] [--out profile.json]
deckstrap status profile.json      # what the Deck has vs what the profile wants
deckstrap list | doctor | validate profile.json | version
```

`./build.sh --profile P --assets DIR --out deckstrap.sh` packs the tool, the
profile and the assets folder into one self-extracting script. Run it on the
Deck with `bash deckstrap.sh`; it accepts the same options as `apply`, plus
`status`, `list` and `doctor`.

## Profile

`deckstrap export` reads a Decky `homebrew` folder and writes everything the
tool needs. The interesting part:

| Profile key | Comes from | Used for |
|---|---|---|
| `decky.plugins` | `settings/loader.json` pluginOrder | plugins to install fresh from the Decky store, in order |
| `decky.settings` | every file under `settings/` | written back as-is (JSON inline, text as strings); `loader.json` is merged so Decky's own user info is kept |
| `decky.themes[]` | each `themes/<theme>/theme.json` id + `config_USER.json` | theme fetched fresh from deckthemes by id, then its enabled state and patch choices re-applied |
| `decky.profiles[]` | `themes/<name>.profile/` | CSS Loader profiles are user-made, so they are written from the profile |
| `decky.css_store` | `themes/STORE` | CSS Loader store preferences |
| `decky.sounds` | `sounds/<pack>/pack.json` id + `sounds/config.json` | pack fetched fresh, selection re-applied |

Themes or packs with no store id are listed under `themes_local` and can only
be restored from `assets/themes/<name>`. `--redact` blanks values whose key
looks like an API key or token and lists them so a profile can be shared.

Assets are optional files the profile cannot describe: `assets/home` (dotfiles
rsynced over `$HOME`), `assets/bios` (EmuDeck BIOS files), `assets/themes` and
`assets/sounds` (local-only items). `apply` looks for `assets/` next to the
profile unless `--assets` is given.

See [profile.example.json](profile.example.json) for every key.

## Modules

| Module | Default | Does |
|---|---|---|
| home | on if assets/home exists | rsync dotfiles over `$HOME` |
| system | on | SSH on, optional authorized key, hostname, timezone |
| flatpaks | on | Firefox, ProtonUp-Qt, Flatseal from Flathub (edit the list) |
| firefox | on | enterprise policy: force-install extensions, homepage, no telemetry, default browser |
| decky | on | loader, plugins, settings, themes, sounds, restart |
| ge_proton | on | latest GE-Proton, sha512 verified |
| cryoutilities | on | install and apply recommended settings |
| flatpak_auto_update | on | daily systemd user timer |
| desktop | on | screen lock off, shell aliases; dark theme and git identity optional |
| distrobox | off | Arch container with CLI tools exported to `~/.local/bin` |
| pacman | off | writable rootfs; wiped by SteamOS updates |
| emudeck | off / bios if assets/bios exists | EmuDeck GUI installer, BIOS files into Emulation/bios |
| os_update_check | on | report only |

Adding a module is one file in `modules/` that sets `MOD_NAME`, `MOD_DESC` and
defines `mod_<name>_wanted` and `mod_<name>_apply` (optionally `_check` for
`status` and `_notes` for the end-of-run reminders). Modules run in filename
order.

## Development

```
bash tests/run.sh      # syntax, shellcheck, profile tool, dry-run apply, bundle build
./build.sh             # dist/deckstrap.sh from profile.example.json with the module picker
```

Releases: push a tag `vX.Y.Z` and the release workflow attaches
`deckstrap.sh` and its sha256 to the GitHub release. The website in `docs/`
is served by GitHub Pages (Settings > Pages > main, /docs) and its installer
`.desktop` file always fetches the latest release.

Requirements on the Deck: SteamOS 3.5 or newer, Desktop Mode, internet. Only
tools that ship with SteamOS are used (bash, python3, curl, rsync, flatpak,
systemd, zenity, konsole).

## License

MIT. Not affiliated with Valve, the Decky project, or any plugin or theme author.
