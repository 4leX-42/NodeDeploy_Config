<#
.SYNOPSIS
    Compara dos ejecuciones del laboratorio (p.ej. v4 vs v5): duracion total y por app, estado e intentos.
.EXAMPLE
    .\Compare-LabResults.ps1 -Before .\results\20260924_190000_antes -After .\results\20260924_191500_v5
#>
param(
    [Parameter(Mandatory)][string]$Before,
    [Parameter(Mandatory)][string]$After,
    [string]$OutFile
)

function Read-Run([string]$dir) {
    $res   = Get-ChildItem $dir -Recurse -Filter 'result.json' | Select-Object -First 1
    $state = Get-ChildItem $dir -Recurse -Filter 'nodedeploy_state.json' | Select-Object -First 1
    $r = if ($res) { Get-Content $res.FullName -Raw | ConvertFrom-Json } else { $null }
    $apps = @{}
    if ($state) {
        $s = Get-Content $state.FullName -Raw | ConvertFrom-Json
        foreach ($p in $s.apps.PSObject.Properties) { $apps[$p.Name] = $p.Value }
    }
    return @{ Result = $r; Apps = $apps }
}

$b = Read-Run $Before
$a = Read-Run $After
# Alias de nombres entre versiones
$alias = @{ 'Microsoft 365 Apps' = 'Outlook clasico' }

$names = @($b.Apps.Keys | ForEach-Object { if ($alias[$_]) { $alias[$_] } else { $_ } }) + @($a.Apps.Keys) | Sort-Object -Unique
$rows = foreach ($n in $names) {
    $bn = ($alias.GetEnumerator() | Where-Object { $_.Value -eq $n } | Select-Object -First 1).Key
    $br = if ($b.Apps[$n]) { $b.Apps[$n] } elseif ($bn) { $b.Apps[$bn] } else { $null }
    $ar = $a.Apps[$n]
    [pscustomobject]@{
        App          = $n
        'Antes s'    = $(if ($br) { $br.elapsed_sec } else { '-' })
        'Antes est.' = $(if ($br) { $br.status } else { '-' })
        'Despues s'  = $(if ($ar) { $ar.elapsed_sec } else { '-' })
        'Despues est.' = $(if ($ar) { $ar.status } else { '-' })
        'Intentos'   = $(if ($ar) { $ar.attempts } else { '-' })
    }
}

$sb = New-Object Text.StringBuilder
[void]$sb.AppendLine("# Comparativa laboratorio")
[void]$sb.AppendLine('')
[void]$sb.AppendLine("| | Antes ($($b.Result.version)) | Despues ($($a.Result.version)) |")
[void]$sb.AppendLine('|---|---|---|')
[void]$sb.AppendLine("| Duracion total | $($b.Result.seconds)s ($([math]::Round($b.Result.seconds/60,1)) min) | $($a.Result.seconds)s ($([math]::Round($a.Result.seconds/60,1)) min) |")
[void]$sb.AppendLine("| Exit | $($b.Result.exit) | $($a.Result.exit) |")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('| App | Antes (s) | Estado | Despues (s) | Estado | Intentos |')
[void]$sb.AppendLine('|---|---|---|---|---|---|')
foreach ($r in $rows) { [void]$sb.AppendLine("| $($r.App) | $($r.'Antes s') | $($r.'Antes est.') | $($r.'Despues s') | $($r.'Despues est.') | $($r.Intentos) |") }
$md = $sb.ToString()
if ($OutFile) { Set-Content -Path $OutFile -Value $md -Encoding UTF8 }
$md
