# Steam Deck test VM

Real SteamOS in QEMU, built from Valve's official recovery image, so deckstrap
can be exercised against the actual OS: read-only root, Flatpak, the `deck`
user with no password, Decky's installer, zenity, Konsole. Gaming Mode does
not render in a VM (no GPU passthrough); Desktop Mode does, and that is where
deckstrap runs.

Two equivalent scripts: `steamos-vm.ps1` for Windows (QEMU with WHPX
acceleration) and `steamos-vm.sh` for Linux (QEMU/KVM). Files live in
`~/VMs/steamos` (about 11 GB after setup: 2.4 GB download, 8 GB unpacked
recovery image, plus the sparse system disk that grows to ~20 GB).

## One-time setup

```powershell
.\vm\steamos-vm.ps1 setup
```

Installs QEMU via winget if needed (approve the UAC prompt), downloads and
unpacks the recovery image, creates an 80 GB sparse NVMe disk. The installer
only re-images a disk it sees as `/dev/nvme0n1`, which is why the VM uses an
emulated NVMe controller rather than SATA.

```powershell
.\vm\steamos-vm.ps1 install
```

Boots the recovery image. In the VM desktop that appears, double-click
**Re-image Steam Deck**, confirm, and wait (10 to 20 minutes). When it says it
is done, close the QEMU window.

```powershell
.\vm\steamos-vm.ps1 run
```

First boot of the installed system. SteamOS tries to start Gaming Mode, which
cannot render in the VM, so you may get a black screen or a looping Steam
logo. Switch to a text console with **Ctrl+Alt+F3**, log in as `deck` (no
password), then:

```bash
passwd                                  # choose a sudo password
steamos-session-select plasma-persistent   # make Desktop Mode the default
sudo reboot
```

After the reboot you land in Desktop Mode. Then save the clean state:

```powershell
.\vm\steamos-vm.ps1 snapshot -Name fresh
```

## Test loop

```powershell
.\vm\steamos-vm.ps1 restore -Name fresh      # back to a clean SteamOS in seconds
.\vm\steamos-vm.ps1 run
```

Get a bundle into the VM. Easiest is SSH once the `system` module (or you,
with `sudo systemctl enable --now sshd`) has turned it on; port 2222 on the
host forwards to the VM:

```powershell
.\vm\steamos-vm.ps1 push -File ..\deck-backup\dist\deckstrap.sh
.\vm\steamos-vm.ps1 ssh
```

Inside the VM: `bash ~/deckstrap.sh` for the full GUI flow (Firefox kiosk
in the VM's Desktop Mode), `bash ~/deckstrap.sh wizard` for the dialog, or
`bash ~/deckstrap.sh apply --dry-run`. Before sshd exists, download the
bundle from the website inside the VM's browser, or from a web server on the
host: on the host `python -m http.server 8000` in the folder holding the
bundle, then in the VM `curl -O http://10.0.2.2:8000/deckstrap.sh` (10.0.2.2
is the host from inside QEMU user networking).

The launcher flow can be tested too: open https://jamieemb.github.io/deckstrap/
in the VM's Firefox and download the installer.

## What the VM cannot test

- Gaming Mode, Decky's in-game UI and CSS themes rendering. Files land in the
  right places and `plugin_loader` runs; whether a theme looks right needs a
  Deck.
- Performance of CryoUtilities tweaks, Bluetooth, the real SD card path.
- SteamOS updates behave as on hardware, so "run again after an update" can
  be tested by updating the VM.

## Notes

- Speed: WHPX needs the Windows feature "Windows Hypervisor Platform"
  (Settings > Optional features > More Windows features). Without it QEMU
  silently falls back to software emulation, which still works but is slow.
  Docker Desktop / WSL2 users usually have the related Hyper-V bits on
  already.
- Display: the default is a plain virtio GPU with software rendering in the
  guest, which is enough for Desktop Mode. Try `-Gl` for OpenGL if your QEMU
  build supports it.
- Alternatives: VirtualBox and VMware also work if you give the VM an NVMe
  controller and EFI; this repo scripts QEMU because it needs no GUI setup
  and coexists with Hyper-V.
