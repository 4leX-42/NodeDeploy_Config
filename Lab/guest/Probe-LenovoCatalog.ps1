<#
    Se ejecuta DENTRO de la VM: instala el modulo oficial Lenovo.Client.Update (PSGallery) y consulta el catalogo
    del ThinkPad L14 (solo lectura: no instala ninguna actualizacion) para ver los campos que devuelve.
#>
$out = 'C:\LabRun\lenovo_probe.txt'
New-Item -ItemType Directory -Force -Path 'C:\LabRun' | Out-Null
function Log([string]$s) { Add-Content -Path $out -Value $s -Encoding UTF8 }
Set-Content -Path $out -Value "== Lenovo probe $(Get-Date -Format s)" -Encoding UTF8
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $sw = [Diagnostics.Stopwatch]::StartNew()
    if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue | Where-Object { $_.Version -ge [version]'2.8.5.201' })) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
    }
    Install-Module -Name Lenovo.Client.Update -Force -Scope AllUsers -AllowClobber -ErrorAction Stop
    Import-Module Lenovo.Client.Update -ErrorAction Stop
    $m = Get-Module Lenovo.Client.Update
    Log "modulo $($m.Version) instalado en $([int]$sw.Elapsed.TotalSeconds) s; comandos: $((Get-Command -Module Lenovo.Client.Update).Name -join ', ')"
    Log "fabricante de la VM: $((Get-CimInstance Win32_ComputerSystem).Manufacturer)"
    $cmd = Get-Command Get-LnvUpdate
    Log "Get-LnvUpdate parametros: $(($cmd.Parameters.Keys | Where-Object { $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters }) -join ', ')"
    Log "Install-LnvUpdate parametros: $(((Get-Command Install-LnvUpdate).Parameters.Keys | Where-Object { $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters }) -join ', ')"
    foreach ($model in '21C1', '20U1') {
        $sw.Restart()
        try {
            $u = @(Get-LnvUpdate -Model $model -All -ErrorAction Stop)
            Log "--- modelo $model : $($u.Count) paquetes en $([int]$sw.Elapsed.TotalSeconds) s"
            if ($u) {
                Log "propiedades: $(($u[0].PSObject.Properties.Name) -join ', ')"
                Log "instalador: $(($u[0].Installer.PSObject.Properties.Name) -join ', ')"
                $u | Select-Object -First 25 | ForEach-Object { Log ("  [{0}] reboot={1} desatendido={2} cat={3} :: {4}" -f $_.Type, $_.RebootType, $_.Installer.Unattended, $_.Category, $_.Title) }
                Log ("  tipos: " + (($u | Group-Object Type | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', '))
                Log ("  rebootType: " + (($u | Group-Object RebootType | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', '))
                break
            }
        } catch { Log "--- modelo $model : ERROR $($_.Exception.Message)" }
    }
    exit 0
} catch {
    Log "EXCEPCION: $($_.Exception.Message)"
    exit 1
}
