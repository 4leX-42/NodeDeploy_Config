<#
.SYNOPSIS
    Escribe en la VM de laboratorio via VNC (127.0.0.1), sin VMware Tools. Plan B para rescatar
    una instalacion desatendida atascada (p.ej. lanzar un comando con Win+R).
.EXAMPLE
    .\Send-LabKeys.ps1 -WinR 'powershell -ep bypass -file E:\lab-firstlogon.ps1'
    .\Send-LabKeys.ps1 -Text 'hola' -Enter
.NOTES
    El .vmx usa RemoteDisplay.vnc.keyMap = "es" para que los caracteres especiales coincidan con
    el teclado es-ES del invitado.
#>
param(
    [string]$Text,
    [string]$WinR,
    [switch]$Enter,
    [int]$Port = 0
)
$ErrorActionPreference = 'Stop'
if (-not $Port) {
    $cfgPath = Join-Path $PSScriptRoot 'lab.local.json'
    $Port = if (Test-Path $cfgPath) { [int](Get-Content $cfgPath -Raw | ConvertFrom-Json).VncPort } else { 5971 }
    if (-not $Port) { $Port = 5971 }
}
function Read-Exact([IO.Stream]$s, [int]$n) {
    $buf = New-Object byte[] $n; $off = 0
    while ($off -lt $n) { $r = $s.Read($buf, $off, $n - $off); if ($r -le 0) { throw 'VNC cerrado' }; $off += $r }
    return ,$buf
}
$tcp = New-Object Net.Sockets.TcpClient('127.0.0.1', $Port); $s = $tcp.GetStream()
try {
    [void](Read-Exact $s 12)
    $b = [Text.Encoding]::ASCII.GetBytes("RFB 003.008`n"); $s.Write($b, 0, $b.Length)
    $n = (Read-Exact $s 1)[0]; [void](Read-Exact $s $n); $s.WriteByte(1); [void](Read-Exact $s 4)
    $s.WriteByte(1)
    $init = Read-Exact $s 24
    $nameLen = ([int]$init[20] -shl 24) -bor ([int]$init[21] -shl 16) -bor ([int]$init[22] -shl 8) -bor [int]$init[23]
    if ($nameLen) { [void](Read-Exact $s $nameLen) }

    function Send-Key([uint32]$keysym, [bool]$down) {
        $msg = [byte[]](4, [byte]$down, 0, 0, [byte](($keysym -shr 24) -band 255), [byte](($keysym -shr 16) -band 255), [byte](($keysym -shr 8) -band 255), [byte]($keysym -band 255))
        $s.Write($msg, 0, 8); $s.Flush()
    }
    function Tap([uint32]$keysym) { Send-Key $keysym $true; Start-Sleep -Milliseconds 25; Send-Key $keysym $false; Start-Sleep -Milliseconds 25 }
    function Type-String([string]$t) { foreach ($ch in $t.ToCharArray()) { Tap ([uint32][char]$ch) } }

    if ($WinR) {
        Send-Key 0xffeb $true; Tap ([uint32][char]'r'); Send-Key 0xffeb $false   # Super_L + r
        Start-Sleep -Milliseconds 900
        Type-String $WinR
        Start-Sleep -Milliseconds 300
        Tap 0xff0d
    }
    if ($Text) { Type-String $Text }
    if ($Enter) { Tap 0xff0d }
    'OK'
} finally { $tcp.Close() }
