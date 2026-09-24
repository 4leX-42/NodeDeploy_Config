<#
    Se ejecuta DENTRO de la VM de laboratorio.
    Simula el Office de fabrica de un portatil Lenovo: Microsoft 365 Apps for business (O365BusinessRetail),
    Current Channel, build de hace unos meses (2605 = 16.0.20026.20112), es-es, SIN Outlook clasico.
    Se instala desde el payload local del repo (1.Node_Preparation\Office\Data) -> sin descarga.
    Tras instalar se borra la copia local: el paso Outlook de NodeDeploy tendra que ir al CDN,
    igual que en un portatil real.
#>
$ErrorActionPreference = 'Stop'
$share   = '\\vmware-host\Shared Folders\nodedeploy\1.Node_Preparation'
$work    = 'C:\LabRun\odt'
$srcRoot = Join-Path $work 'src'
$log     = 'C:\LabRun\baseline_office.log'
$build   = '16.0.20026.20112'

function Log($m) { $l = "$(Get-Date -Format 'HH:mm:ss') $m"; Add-Content -Path $log -Value $l; Write-Output $l }

New-Item -ItemType Directory -Force -Path $work, (Join-Path $srcRoot 'Office\Data') | Out-Null
Log "Copiando ODT + payload $build desde el share..."
Copy-Item (Join-Path $share 'OfficeSetup.exe') (Join-Path $work 'setup.exe') -Force
robocopy (Join-Path $share 'Office\Data') (Join-Path $srcRoot 'Office\Data') /E /NFL /NDL /NJH /NJS /R:2 /W:2 | Out-Null
if ($LASTEXITCODE -ge 8) { Log "robocopy fallo ($LASTEXITCODE)"; exit 10 }

$xml = @"
<Configuration ID="Lab-Lenovo-OEM-Baseline">
  <Add SourcePath="$srcRoot" OfficeClientEdition="64" Channel="Current" Version="$build" AllowCdnFallback="FALSE">
    <Product ID="O365BusinessRetail">
      <Language ID="es-es" />
      <ExcludeApp ID="Outlook" />
      <ExcludeApp ID="Groove" />
      <ExcludeApp ID="Lync" />
      <ExcludeApp ID="Bing" />
    </Product>
  </Add>
  <Updates Enabled="FALSE" />
  <Display Level="None" AcceptEULA="TRUE" />
  <Logging Level="Standard" Path="C:\LabRun\odtlogs" />
  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />
</Configuration>
"@
$xmlPath = Join-Path $work 'baseline.xml'
Set-Content -Path $xmlPath -Value $xml -Encoding UTF8

Log "Instalando O365BusinessRetail $build sin Outlook..."
$sw = [Diagnostics.Stopwatch]::StartNew()
$p = Start-Process -FilePath (Join-Path $work 'setup.exe') -ArgumentList "/configure `"$xmlPath`"" -Wait -PassThru
Log "ODT exit $($p.ExitCode) en $([int]$sw.Elapsed.TotalSeconds)s"

$root = "$env:ProgramFiles\Microsoft Office\root\Office16"
$word = Test-Path (Join-Path $root 'WINWORD.EXE')
$outl = Test-Path (Join-Path $root 'OUTLOOK.EXE')
Log "WINWORD=$word OUTLOOK=$outl"

Log 'Borrando payload local (el paso Outlook real va al CDN)...'
Remove-Item $srcRoot -Recurse -Force -ErrorAction SilentlyContinue

if ($p.ExitCode -ne 0 -or -not $word -or $outl) { Log 'BASELINE KO'; exit 20 }
Log 'BASELINE OK (Word presente, Outlook ausente)'
exit 0
