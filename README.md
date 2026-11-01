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
Desktop Mode. A full-screen installer opens, sized for the Deck's display.
See [docs/index.html](docs/index.html).

**Rebuilding your own Deck:** export a profile once, build a bundle that
carries it, keep the bundle on a USB stick.

## The installer UI

`deckstrap gui profile.json` starts a small local backend (`lib/server.py`,
Python standard library only) that serves `ui/index.html` and runs
`deckstrap apply` on request, streaming progress. The page opens in Firefox
kiosk mode, full screen, with a private pre-configured profile; if Firefox is
not installed yet it is fetched from Flathub first behind a progress dialog.
Screens: welcome, choose modules, sudo password (set or enter), live progress
with step list and log, finished with next steps and a Return to Gaming Mode
button. The backend binds to 127.0.0.1 on a random port and requires a random
token on every call. The sudo password is passed to the apply process only
through its environment and a `SUDO_ASKPASS` helper; it is never written to
disk or logged. Without a display, or if Firefox cannot be installed, it falls
back to the zenity checklist or a terminal prompt.

## Commands

```
deckstrap gui profile.json [--assets DIR] [--dry-run]
deckstrap apply profile.json [--only a,b] [--skip a,b] [--dry-run] [--wizard] [--assets DIR]
deckstrap export [--from ~/homebrew] [--name NAME] [--redact] [--out profile.json]
deckstrap status profile.json      # what the Deck has vs what the profile wants
deckstrap modules profile.json     # name / wanted / description, for tooling
deckstrap list | doctor | validate profile.json | version
```

`./build.sh --profile P --assets DIR --out deckstrap.sh [--mode gui|wizard|apply]`
packs the tool, the profile and the assets folder into one self-extracting
script. Run it on the Deck with `bash deckstrap.sh`: in gui mode (the default)
it opens the installer; `bash deckstrap.sh apply` runs unattended and `wizard`
shows the checklist dialog. `status`, `list` and `doctor` work too.

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
bash tests/run.sh      # syntax, shellcheck, profile tool, backend API, dry-run apply, bundle build
./build.sh             # dist/deckstrap.sh from profile.example.json, GUI mode
python3 lib/server.py --profile profile.example.json --insecure-no-sudo   # UI development: open the printed URL with &dry=1
```

**Test VM:** `vm/` has scripts that build a real SteamOS virtual machine
from Valve's recovery image (QEMU; Windows with WHPX or Linux with KVM),
with snapshots for a repeatable clean install. See [vm/README.md](vm/README.md).

Releases: push a tag `vX.Y.Z` and the release workflow attaches
`deckstrap.sh` and its sha256 to the GitHub release. The website in `docs/`
is served by GitHub Pages (Settings > Pages > main, /docs) and its installer
`.desktop` file always fetches the latest release.

Requirements on the Deck: SteamOS 3.5 or newer, Desktop Mode, internet. Only
tools that ship with SteamOS are used (bash, python3, curl, rsync, flatpak,
systemd, zenity, konsole).

## License

MIT. Not affiliated with Valve, the Decky project, or any plugin or theme author.
