<#
.SYNOPSIS
    Crea la VM de laboratorio NodeDeploy-Lab (VMware Workstation) con Windows 11 Pro desatendido
    y deja snapshots listos para probar NodeDeploy sin tocar el host.

.DESCRIPTION
    Etapas (-Stage):
      create   -> genera credenciales, autounattend ISO, disco, .vmx y arranca la instalacion.
      wait     -> espera a Windows + VMware Tools y crea snapshot '00-clean-os'.
      baseline -> simula portatil Lenovo: Microsoft 365 Apps for business SIN Outlook clasico
                  (Word/Excel/PPT presentes, Outlook ausente) y crea snapshot '01-lenovo-baseline'.
      all      -> las tres seguidas.

    La VM:
      - firmware BIOS (instalacion sin pulsar tecla), sin vTPM (no requiere cifrado).
      - carpeta compartida SOLO LECTURA con el repo (\\vmware-host\Shared Folders\nodedeploy).
      - Defender activo, Windows Update pausado, UAC desactivado (solo dentro de la VM).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\New-NodeDeployLab.ps1 -Stage all
#>
[CmdletBinding()]
param(
    [ValidateSet('create','wait','baseline','all')]
    [string]$Stage = 'all',
    [string]$VmDir = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Virtual Machines\NodeDeploy-Lab'),
    [string]$WindowsIso = 'C:\ISO\Win11_25H2_Spanish_x64_v2.iso',
    [int]$MemoryMB = 4096,
    [int]$Cpus = 4,
    [int]$DiskGB = 80,
    [int]$VncPort = 5971,      # VNC solo en 127.0.0.1: Get-LabScreenshot.ps1 ve la pantalla sin VMware Tools
    [switch]$Gui
)

. (Join-Path $PSScriptRoot 'LabCommon.ps1')

$vmName   = 'NodeDeploy-Lab'
$vmxPath  = Join-Path $VmDir "$vmName.vmx"
$buildDir = Join-Path $Script:LabRoot '_build'
$wsDir    = Split-Path -Parent $Script:VmrunExe
$toolsIso = Join-Path $wsDir 'windows.iso'
$vdiskMgr = Join-Path $wsDir 'vmware-vdiskmanager.exe'

function New-LabIso {
    <# ISO ISO9660+Joliet con el contenido de $SourceDir (IMAPI2, nativo de Windows). #>
    param([string]$SourceDir, [string]$IsoPath, [string]$Label)
    if (-not ('LabIsoWriter' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
public static class LabIsoWriter {
    public static void Write(object comStream, string path, int blockSize, int totalBlocks) {
        IStream input = (IStream)comStream;
        byte[] buffer = new byte[blockSize];
        IntPtr pRead = Marshal.AllocHGlobal(sizeof(int));
        try {
            using (FileStream output = File.Create(path)) {
                for (int i = 0; i < totalBlocks; i++) {
                    input.Read(buffer, blockSize, pRead);
                    output.Write(buffer, 0, Marshal.ReadInt32(pRead));
                }
            }
        } finally { Marshal.FreeHGlobal(pRead); }
    }
}
'@
    }
    $fsi = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
    $fsi.FileSystemsToCreate = 3   # ISO9660 | Joliet
    $fsi.VolumeName = $Label
    $fsi.Root.AddTree($SourceDir, $false)
    $img = $fsi.CreateResultImage()
    [LabIsoWriter]::Write($img.ImageStream, $IsoPath, $img.BlockSize, $img.TotalBlocks)
}

function New-LabPassword {
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'.ToCharArray()
    $bytes = New-Object byte[] 16
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return 'Nd-' + (-join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] }))
}

function Invoke-StageCreate {
    Write-LabLog "=== CREATE: $vmName ===" 'STEP'
    foreach ($req in @($WindowsIso, $toolsIso, $vdiskMgr)) {
        if (-not (Test-Path $req)) { throw "Falta requisito: $req" }
    }
    if (Test-Path $vmxPath) { throw "Ya existe $vmxPath. Borra la carpeta de la VM si quieres recrearla." }
    New-Item -ItemType Directory -Force -Path $VmDir, $buildDir | Out-Null

    # 1) Credenciales locales del laboratorio (fuera de git: lab.local.json esta en .gitignore)
    $cfg = [pscustomobject]@{
        VmxPath       = $vmxPath
        GuestUser     = 'labadmin'
        GuestPassword = New-LabPassword
        Computer      = 'NDLAB01'
        SharedFolder  = 'nodedeploy'
        VncPort       = $VncPort
        HostRepo      = $Script:RepoRoot
        Created       = (Get-Date -Format 'o')
    }
    $cfg | ConvertTo-Json | Set-Content -Path $Script:LabLocalCfg -Encoding UTF8
    Write-LabLog "Credenciales guardadas en $($Script:LabLocalCfg) (usuario $($cfg.GuestUser))" 'OK'

    # 2) autounattend.xml -> ISO
    $unattendDir = Join-Path $buildDir 'unattend'
    New-Item -ItemType Directory -Force -Path $unattendDir | Out-Null
    $xml = Get-Content (Join-Path $Script:LabRoot 'templates\autounattend.template.xml') -Raw
    $xml = $xml.Replace('__LAB_USER__', $cfg.GuestUser).Replace('__LAB_PASSWORD__', $cfg.GuestPassword).Replace('__LAB_COMPUTER__', $cfg.Computer)
    [IO.File]::WriteAllText((Join-Path $unattendDir 'autounattend.xml'), $xml, (New-Object Text.UTF8Encoding($false)))
    Copy-Item (Join-Path $Script:LabRoot 'templates\lab-firstlogon.ps1') (Join-Path $unattendDir 'lab-firstlogon.ps1') -Force
    # VMware no monta windows.iso como CD normal (la trata como "Tools ISO", capacity=0):
    # su contenido va dentro de la ISO desatendida y lab-firstlogon.ps1 lo encuentra ahi.
    $toolsDir = Join-Path $unattendDir 'vmtools'
    New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
    $sevenZip = @("$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($sevenZip) {
        & $sevenZip x $toolsIso "-o$toolsDir" -y | Out-Null
    } else {
        $img = Mount-DiskImage -ImagePath $toolsIso -Access ReadOnly -PassThru
        try { Copy-Item "$(($img | Get-Volume).DriveLetter):\*" $toolsDir -Recurse -Force } finally { Dismount-DiskImage -ImagePath $toolsIso | Out-Null }
    }
    if (-not ((Test-Path (Join-Path $toolsDir 'setup.exe')) -or (Test-Path (Join-Path $toolsDir 'setup64.exe')))) { throw "No se pudo extraer VMware Tools de $toolsIso" }
    $unattendIso = Join-Path $VmDir 'lab-autounattend.iso'
    New-LabIso -SourceDir $unattendDir -IsoPath $unattendIso -Label 'AUTOUNATTEND'
    Remove-Item (Join-Path $unattendDir 'autounattend.xml') -Force   # no dejar la password en claro en _build
    Write-LabLog "ISO desatendida: $unattendIso" 'OK'

    # 3) Disco NVMe growable
    $vmdk = Join-Path $VmDir "$vmName.vmdk"
    & $vdiskMgr -c -s "${DiskGB}GB" -a lsilogic -t 0 $vmdk | Out-Null
    if (-not (Test-Path $vmdk)) { throw "vmware-vdiskmanager no creo $vmdk" }
    Write-LabLog "Disco ${DiskGB}GB creado" 'OK'

    # 4) .vmx
    $repo = $Script:RepoRoot
    $vmx = @"
.encoding = "windows-1252"
config.version = "8"
virtualHW.version = "21"
displayName = "$vmName"
guestOS = "windows9-64"
firmware = "bios"
bios.bootDelay = "0"
memsize = "$MemoryMB"
numvcpus = "$Cpus"
cpuid.coresPerSocket = "$Cpus"
mem.hotadd = "TRUE"
mks.enable3d = "FALSE"
svga.graphicsMemoryKB = "262144"
pciBridge0.present = "TRUE"
pciBridge4.present = "TRUE"
pciBridge4.virtualDev = "pcieRootPort"
pciBridge4.functions = "8"
pciBridge5.present = "TRUE"
pciBridge5.virtualDev = "pcieRootPort"
pciBridge5.functions = "8"
pciBridge6.present = "TRUE"
pciBridge6.virtualDev = "pcieRootPort"
pciBridge6.functions = "8"
pciBridge7.present = "TRUE"
pciBridge7.virtualDev = "pcieRootPort"
pciBridge7.functions = "8"
vmci0.present = "TRUE"
hpet0.present = "TRUE"
nvme0.present = "TRUE"
nvme0:0.present = "TRUE"
nvme0:0.fileName = "$vmName.vmdk"
sata0.present = "TRUE"
sata0:0.present = "TRUE"
sata0:0.deviceType = "cdrom-image"
sata0:0.fileName = "$WindowsIso"
sata0:1.present = "TRUE"
sata0:1.deviceType = "cdrom-image"
sata0:1.fileName = "$unattendIso"
ethernet0.present = "TRUE"
ethernet0.connectionType = "nat"
ethernet0.virtualDev = "e1000e"
ethernet0.addressType = "generated"
usb.present = "TRUE"
ehci.present = "TRUE"
usb_xhci.present = "TRUE"
sound.present = "FALSE"
floppy0.present = "FALSE"
tools.syncTime = "TRUE"
tools.upgrade.policy = "manual"
tools.remindInstall = "FALSE"
msg.autoAnswer = "TRUE"
uuid.action = "keep"
isolation.tools.hgfs.disable = "FALSE"
sharedFolder.maxNum = "1"
sharedFolder0.present = "TRUE"
sharedFolder0.enabled = "TRUE"
sharedFolder0.readAccess = "TRUE"
sharedFolder0.writeAccess = "FALSE"
sharedFolder0.hostPath = "$repo"
sharedFolder0.guestName = "$($cfg.SharedFolder)"
sharedFolder0.expiration = "never"
RemoteDisplay.vnc.enabled = "TRUE"
RemoteDisplay.vnc.ip = "127.0.0.1"
RemoteDisplay.vnc.port = "$VncPort"
RemoteDisplay.vnc.keyMap = "es"
annotation = "NodeDeploy lab VM (creada por Lab\\New-NodeDeployLab.ps1). Solo pruebas: NO usar para datos reales."
"@
    Set-Content -Path $vmxPath -Value $vmx -Encoding ASCII
    Write-LabLog "VMX: $vmxPath" 'OK'

    # 5) Arranque -> instalacion desatendida (~20-40 min segun host)
    $mode = if ($Gui) { 'gui' } else { 'nogui' }
    Invoke-Vmrun -Arguments @('start', $vmxPath, $mode) | Out-Null
    Write-LabLog "VM arrancada ($mode). Windows se instala solo; siguiente: -Stage wait" 'OK'
}

function Invoke-StageWait {
    Write-LabLog '=== WAIT: Windows + VMware Tools ===' 'STEP'
    $cfg = Get-LabConfig
    if (-not (Test-LabRunning $cfg)) { Invoke-Vmrun -Arguments @('start', $cfg.VmxPath, 'nogui') | Out-Null }
    Wait-LabTools -Config $cfg -TimeoutMin 120 | Out-Null
    # Tras FirstLogonCommands la VM reinicia una vez: esperar marcador + tools estables.
    $sw = [Diagnostics.Stopwatch]::StartNew()
    do {
        Start-Sleep -Seconds 20
        $m = Invoke-Vmrun -Guest -Config $cfg -AllowFail -Arguments @('fileExistsInGuest', $cfg.VmxPath, 'C:\lab_ready.txt')
    } until ($m.Output -match 'exists' -or $sw.Elapsed.TotalMinutes -gt 30)
    Start-Sleep -Seconds 60   # margen para el reinicio final de FirstLogonCommands
    Wait-LabTools -Config $cfg -TimeoutMin 30 | Out-Null

    Invoke-LabGuestScript -Config $cfg -ScriptPath (Join-Path $Script:LabRoot 'guest\Get-LabGuestInfo.ps1') | Out-Null
    $info = Join-Path $buildDir 'guestinfo.txt'
    Copy-FromLabGuest -Config $cfg -GuestPath 'C:\LabRun\guestinfo.txt' -HostPath $info | Out-Null
    if (Test-Path $info) { Write-LabLog "Invitado: $(Get-Content $info -Raw)" 'INFO' }

    Invoke-Vmrun -Arguments @('snapshot', $cfg.VmxPath, '00-clean-os') | Out-Null
    Write-LabLog "Snapshot '00-clean-os' creado" 'OK'
}

function Invoke-StageBaseline {
    Write-LabLog '=== BASELINE: Microsoft 365 Apps sin Outlook clasico (simula Lenovo) ===' 'STEP'
    $cfg = Get-LabConfig
    Wait-LabTools -Config $cfg -TimeoutMin 20 | Out-Null
    Set-LabShareToRepo -Config $cfg
    $ps = Join-Path $Script:LabRoot 'guest\Install-LenovoOfficeBaseline.ps1'
    $r = Invoke-LabGuestScript -Config $cfg -ScriptPath $ps -Interactive
    $blog = Join-Path $buildDir 'baseline_office.log'
    Copy-FromLabGuest -Config $cfg -GuestPath 'C:\LabRun\baseline_office.log' -HostPath $blog | Out-Null
    if (Test-Path $blog) { Get-Content $blog | ForEach-Object { Write-LabLog "  guest> $_" 'INFO' } }
    Write-LabLog "Baseline Office exit=$($r.ExitCode)" $(if ($r.ExitCode -eq 0) { 'OK' } else { 'ERROR' })
    if ($r.ExitCode -ne 0) { throw "Baseline Office fallo (exit $($r.ExitCode)). Log: $blog" }

    # Pre-copia del repo (sin AV) dentro del snapshot: cada prueba solo sincroniza diferencias.
    $s = Invoke-LabGuestScript -Config $cfg -ScriptPath (Join-Path $Script:LabRoot 'guest\Sync-NodeDeploy.ps1')
    Write-LabLog "Sync C:\nodedeploy exit=$($s.ExitCode)" $(if ($s.ExitCode -eq 0) { 'OK' } else { 'WARN' })
    Invoke-Vmrun -Arguments @('snapshot', $cfg.VmxPath, '01-lenovo-baseline') | Out-Null
    Write-LabLog "Snapshot '01-lenovo-baseline' creado" 'OK'
}

switch ($Stage) {
    'create'   { Invoke-StageCreate }
    'wait'     { Invoke-StageWait }
    'baseline' { Invoke-StageBaseline }
    'all'      { Invoke-StageCreate; Invoke-StageWait; Invoke-StageBaseline }
}
