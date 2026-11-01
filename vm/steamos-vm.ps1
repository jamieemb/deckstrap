<#
.SYNOPSIS
  Steam Deck test VM on Windows: real SteamOS in QEMU (WHPX accelerated).

.DESCRIPTION
  Builds and runs a SteamOS virtual machine from Valve's official recovery
  image so deckstrap can be tested against the real OS (read-only root,
  Flatpak, the deck user, Decky's installer). Gaming Mode does not render in
  a VM; Desktop Mode does, which is where deckstrap runs.

  Actions
    setup      install QEMU (winget), download + unpack the recovery image, create the disk
    install    boot the recovery image with an empty NVMe disk: click "Re-image Steam Deck"
    run        boot the installed SteamOS (default action)
    snapshot   save a named qcow2 snapshot of the disk     (-Name fresh)
    restore    roll the disk back to a snapshot            (-Name fresh)
    push       scp a file into the VM's home               (-File path)
    ssh        open a shell in the VM (port 2222 -> 22)
    status     show what exists

  Typical first run:
    .\vm\steamos-vm.ps1 setup
    .\vm\steamos-vm.ps1 install      # in the VM: Re-image Steam Deck, wait, then close QEMU
    .\vm\steamos-vm.ps1 run          # first boot; if the screen stays black see vm/README.md
    .\vm\steamos-vm.ps1 snapshot -Name fresh
    .\vm\steamos-vm.ps1 push -File ..\deck-backup\dist\deckstrap.sh
    .\vm\steamos-vm.ps1 ssh          # then: bash deckstrap.sh

.NOTES
  Needs the "Windows Hypervisor Platform" optional feature for WHPX speed;
  without it QEMU falls back to TCG (software emulation, slow but works).
#>
[CmdletBinding()]
param(
  [ValidateSet('setup','install','run','snapshot','restore','push','ssh','status')]
  [string]$Action = 'run',
  [string]$VmDir = "$env:USERPROFILE\VMs\steamos",
  [int]$MemoryMB = 6144,
  [int]$Cpus = 4,
  [int]$DiskGB = 80,
  [string]$Name = 'fresh',
  [string]$File = '',
  [int]$SshPort = 2222,
  [switch]$Gl,          # try OpenGL for the virtual GPU (virtio-vga-gl); off by default
  [switch]$NoAccel      # force TCG software emulation
)
$ErrorActionPreference = 'Stop'

$RecoveryUrl = 'https://steamdeck-images.steamos.cloud/recovery/steamdeck-recovery-4.img.bz2'
$RecoveryBz2 = Join-Path $VmDir 'steamdeck-recovery-4.img.bz2'
$RecoveryImg = Join-Path $VmDir 'steamdeck-recovery-4.img'
$Disk        = Join-Path $VmDir 'steamos.qcow2'
$Vars        = Join-Path $VmDir 'efi-vars.fd'
$QemuDir     = 'C:\Program Files\qemu'
$Qemu        = Join-Path $QemuDir 'qemu-system-x86_64.exe'
$QemuImg     = Join-Path $QemuDir 'qemu-img.exe'
$EfiCode     = Join-Path $QemuDir 'share\edk2-x86_64-code.fd'
$EfiVarsTpl  = Join-Path $QemuDir 'share\edk2-i386-vars.fd'

function Say($m) { Write-Host "[vm] $m" -ForegroundColor Cyan }
function Need-Qemu {
  if (-not (Test-Path $Qemu)) { throw "QEMU not found at $QemuDir. Run: .\vm\steamos-vm.ps1 setup" }
}

function Do-Setup {
  New-Item -ItemType Directory -Force $VmDir | Out-Null
  if (-not (Test-Path $Qemu)) {
    Say 'installing QEMU with winget (approve the UAC prompt if it appears)'
    winget install -e --id SoftwareFreedomConservancy.QEMU --accept-source-agreements --accept-package-agreements
    if (-not (Test-Path $Qemu)) { throw 'QEMU install did not complete' }
  }
  Say "QEMU: $Qemu"
  if (-not (Test-Path $RecoveryImg)) {
    if (-not (Test-Path $RecoveryBz2)) {
      Say "downloading the SteamOS recovery image (about 2.4 GB) from $RecoveryUrl"
      & curl.exe -fL -C - --retry 5 -o $RecoveryBz2 $RecoveryUrl
    }
    Say 'unpacking (bzip2, a few minutes, about 8 GB)'
    $bz = (Get-Command bzip2 -ErrorAction SilentlyContinue).Source
    if (-not $bz) { $bz = 'C:\Program Files\Git\mingw64\bin\bzip2.exe' }
    if (-not (Test-Path $bz)) { throw 'bzip2 not found (Git for Windows ships one)' }
    & $bz -dk $RecoveryBz2
  }
  Say "recovery image: $RecoveryImg"
  if (-not (Test-Path $Disk)) {
    Say "creating ${DiskGB} GB sparse disk $Disk"
    & $QemuImg create -f qcow2 $Disk "${DiskGB}G" | Out-Null
  }
  if (-not (Test-Path $Vars)) { Copy-Item $EfiVarsTpl $Vars }
  Say 'ready. Next: .\vm\steamos-vm.ps1 install'
}

function Accel-Args {
  if ($NoAccel) { return @('-accel','tcg,thread=multi') }
  # WHPX when the Windows Hypervisor Platform is available, else TCG
  return @('-accel','whpx,kernel-irqchip=off','-accel','tcg,thread=multi')
}

function Base-Args {
  Need-Qemu
  if (-not (Test-Path $Vars)) { Copy-Item $EfiVarsTpl $Vars }
  $gpu = if ($Gl) { @('-device','virtio-vga-gl','-display','sdl,gl=on') } else { @('-device','virtio-vga') }
  return @(
    '-name','SteamOS',
    '-machine','q35',
    '-cpu','max',
    '-smp',"$Cpus",
    '-m',"$MemoryMB",
    '-drive',"if=pflash,format=raw,readonly=on,file=$EfiCode",
    '-drive',"if=pflash,format=raw,file=$Vars",
    '-drive',"if=none,id=nvme0,format=qcow2,file=$Disk",
    '-device','nvme,drive=nvme0,serial=deck0001,bootindex=1',
    '-device','qemu-xhci','-device','usb-tablet','-device','usb-kbd',
    '-nic',"user,model=virtio-net-pci,hostfwd=tcp::$SshPort-:22",
    '-rtc','base=localtime',
    '-boot','menu=on'
  ) + $gpu + (Accel-Args)
}

function Do-Install {
  if (-not (Test-Path $RecoveryImg)) { throw 'recovery image missing; run setup first' }
  if (-not (Test-Path $Disk)) { throw 'disk missing; run setup first' }
  Say 'booting the recovery image. In the VM choose "Re-image Steam Deck", confirm, wait for it to finish, then shut the VM down.'
  $a = (Base-Args) + @(
    '-drive',"if=none,id=rec,format=raw,file=$RecoveryImg",
    '-device','usb-storage,drive=rec,bootindex=0'
  )
  & $Qemu @a
}

function Do-Run {
  if (-not (Test-Path $Disk)) { throw 'disk missing; run setup + install first' }
  Say "booting SteamOS (ssh: ssh -p $SshPort deck@localhost once sshd is enabled in the VM)"
  & $Qemu @(Base-Args)
}

function Do-Snapshot { Need-Qemu; & $QemuImg snapshot -c $Name $Disk; Say "snapshot '$Name' saved"; & $QemuImg snapshot -l $Disk }
function Do-Restore  { Need-Qemu; & $QemuImg snapshot -a $Name $Disk; Say "disk rolled back to '$Name'" }
function Do-Push {
  if (-not $File) { throw 'use -File <path>' }
  & scp.exe -P $SshPort -o StrictHostKeyChecking=no $File "deck@localhost:~/"
}
function Do-Ssh { & ssh.exe -p $SshPort -o StrictHostKeyChecking=no deck@localhost }
function Do-Status {
  "QEMU:           $(if (Test-Path $Qemu) { 'installed' } else { 'missing' })"
  "recovery .bz2:  $(if (Test-Path $RecoveryBz2) { '{0:N1} GB' -f ((Get-Item $RecoveryBz2).Length/1GB) } else { 'missing' })"
  "recovery .img:  $(if (Test-Path $RecoveryImg) { '{0:N1} GB' -f ((Get-Item $RecoveryImg).Length/1GB) } else { 'missing' })"
  "disk:           $(if (Test-Path $Disk) { '{0:N1} GB used' -f ((Get-Item $Disk).Length/1GB) } else { 'missing' })"
  if ((Test-Path $Disk) -and (Test-Path $QemuImg)) { & $QemuImg snapshot -l $Disk }
}

switch ($Action) {
  'setup'    { Do-Setup }
  'install'  { Do-Install }
  'run'      { Do-Run }
  'snapshot' { Do-Snapshot }
  'restore'  { Do-Restore }
  'push'     { Do-Push }
  'ssh'      { Do-Ssh }
  'status'   { Do-Status }
}
