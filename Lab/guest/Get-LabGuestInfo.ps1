# Se ejecuta DENTRO de la VM. Resumen rapido del invitado (una linea).
$ErrorActionPreference = 'SilentlyContinue'
$os  = Get-CimInstance Win32_OperatingSystem
$mp  = Get-MpComputerStatus
$c2r = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
$free = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
$line = "{0} build {1} | RAM {2}GB | C: libre {3}GB | Defender RTP={4} | C2R={5} v{6}" -f `
    $os.Caption, $os.BuildNumber, [math]::Round($os.TotalVisibleMemorySize / 1MB, 1), $free,
    $mp.RealTimeProtectionEnabled, $c2r.ProductReleaseIds, $c2r.VersionToReport
$line | Set-Content -Path 'C:\LabRun\guestinfo.txt' -Encoding UTF8
Write-Output $line
exit 0
