<#
    Se ejecuta DENTRO de la VM. Adobe Reader: crea la imagen administrativa con el parche ya aplicado y compara
    el tiempo de instalacion (paquete setup.exe = MSI base + parche en el momento, frente a la imagen parcheada).
    Deja la imagen comprimida en C:\LabRun\AdobeAIP.zip para llevarla al M.2. Nunca en el host.
#>
$ErrorActionPreference = 'Continue'
$src = Get-ChildItem 'C:\nodedeploy\1.Node_Preparation' -Directory -Filter 'AdobeReader_x64_*' | Where-Object Name -notlike '*_AIP' | Select-Object -First 1
$aip = 'C:\LabRun\AdobeAIP'
$out = 'C:\LabRun\adobe_aip.txt'
New-Item -ItemType Directory -Force -Path 'C:\LabRun' | Out-Null
Set-Content -Path $out -Value "== Adobe AIP $(Get-Date -Format s) paquete=$($src.FullName)" -Encoding UTF8
function Log([string]$s) { Add-Content -Path $out -Value $s -Encoding UTF8 }
function Run([string]$Exe, [string]$Arguments) { $p = Start-Process -FilePath $Exe -ArgumentList $Arguments -PassThru -WindowStyle Hidden; $null = $p.Handle; $p.WaitForExit(); return $p.ExitCode }
function Get-AdobeEntry { Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like 'Adobe Acrobat*' } | Select-Object -First 1 }
$props = 'EULA_ACCEPT=YES ENABLE_CHROMEEXT=0 LEAVE_PDFOWNERSHIP=YES'

# 1) Imagen administrativa + parche (no instala nada)
$sw = [Diagnostics.Stopwatch]::StartNew()
if (Test-Path $aip) { Remove-Item $aip -Recurse -Force }
New-Item -ItemType Directory -Force -Path $aip | Out-Null
$msp = Get-ChildItem $src.FullName -Filter '*.msp' | Select-Object -First 1
$e1 = Run 'msiexec.exe' "/a `"$($src.FullName)\AcroPro.msi`" /qn TARGETDIR=`"$aip`" /l*v `"C:\LabRun\aip_admin.log`""
Log "imagen administrativa: exit=$e1 ($([int]$sw.Elapsed.TotalSeconds) s)"
$e2 = Run 'msiexec.exe' "/a `"$aip\AcroPro.msi`" /qn /p `"$($msp.FullName)`" /l*v `"C:\LabRun\aip_patch.log`""
$aipMb = [math]::Round((Get-ChildItem $aip -Recurse -File | Measure-Object Length -Sum).Sum / 1MB)
Log "parche aplicado a la imagen: exit=$e2 ($([int]$sw.Elapsed.TotalSeconds) s), imagen $aipMb MB, $((Get-ChildItem $aip -Recurse -File).Count) ficheros"

# 2) Tiempo con el paquete actual (setup.exe = MSI base + parche al instalar)
$sw.Restart()
$e3 = Run "$($src.FullName)\setup.exe" "/sAll /rs /msi $props"
$t3 = [int]$sw.Elapsed.TotalSeconds; $ent = Get-AdobeEntry
Log "INSTALAR paquete setup.exe: exit=$e3 en $t3 s -> $($ent.DisplayName) v$($ent.DisplayVersion)"
if ($ent) { $e4 = Run 'msiexec.exe' "/x $($ent.PSChildName) /qn /norestart"; Log "  desinstalado: exit=$e4" }
Start-Sleep -Seconds 5

# 3) Tiempo con la imagen ya parcheada
$sw.Restart()
$e5 = Run 'msiexec.exe' "/i `"$aip\AcroPro.msi`" /qn /norestart $props /l*v `"C:\LabRun\aip_install.log`""
$t5 = [int]$sw.Elapsed.TotalSeconds; $ent = Get-AdobeEntry
Log "INSTALAR imagen parcheada: exit=$e5 en $t5 s -> $($ent.DisplayName) v$($ent.DisplayVersion)"

# 4) Imagen comprimida para el M.2
$sw.Restart()
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path 'C:\LabRun\AdobeAIP.zip') { Remove-Item 'C:\LabRun\AdobeAIP.zip' -Force }
[IO.Compression.ZipFile]::CreateFromDirectory($aip, 'C:\LabRun\AdobeAIP.zip', [IO.Compression.CompressionLevel]::Fastest, $false)
Log ("zip: {0} MB en {1} s" -f [math]::Round((Get-Item 'C:\LabRun\AdobeAIP.zip').Length / 1MB), [int]$sw.Elapsed.TotalSeconds)
exit 0
