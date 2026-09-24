<#
.SYNOPSIS
    Captura la pantalla de la VM de laboratorio via VNC (127.0.0.1) y la guarda como PNG.
    Funciona aunque Windows aun no tenga VMware Tools (instalacion, OOBE, pantallazos).
.EXAMPLE
    .\Get-LabScreenshot.ps1 -OutFile .\_build\screen.png
#>
param(
    [string]$OutFile = (Join-Path $PSScriptRoot ("_build\screen_{0}.png" -f (Get-Date -Format 'HHmmss'))),
    [int]$Port = 0
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
if (-not $Port) {
    $cfgPath = Join-Path $PSScriptRoot 'lab.local.json'
    $Port = if (Test-Path $cfgPath) { [int](Get-Content $cfgPath -Raw | ConvertFrom-Json).VncPort } else { 5971 }
    if (-not $Port) { $Port = 5971 }
}

function Read-Exact([IO.Stream]$s, [int]$n) {
    $buf = New-Object byte[] $n; $off = 0
    while ($off -lt $n) {
        $r = $s.Read($buf, $off, $n - $off)
        if ($r -le 0) { throw 'VNC: conexion cerrada' }
        $off += $r
    }
    return ,$buf
}
# Ojo: -shl sobre [byte] se desborda (el resultado sigue siendo byte) -> cast a int/long primero.
function To-U16([byte[]]$b, [int]$i) { return ([int]$b[$i] -shl 8) -bor [int]$b[$i + 1] }
function To-U32([byte[]]$b, [int]$i) { return [uint32](([long]$b[$i] -shl 24) -bor ([long]$b[$i + 1] -shl 16) -bor ([long]$b[$i + 2] -shl 8) -bor [long]$b[$i + 3]) }

$tcp = New-Object Net.Sockets.TcpClient('127.0.0.1', $Port)
$tcp.ReceiveTimeout = 15000
$s = $tcp.GetStream()
try {
    $ver = [Text.Encoding]::ASCII.GetString((Read-Exact $s 12))
    $reply = if ($ver -like 'RFB 003.00[78]*') { 'RFB 003.008' } else { 'RFB 003.003' }
    $b = [Text.Encoding]::ASCII.GetBytes("$reply`n"); $s.Write($b, 0, $b.Length)
    if ($reply -eq 'RFB 003.008') {
        $n = (Read-Exact $s 1)[0]
        if ($n -eq 0) { throw 'VNC: el servidor rechazo la conexion' }
        $types = Read-Exact $s $n
        if ($types -notcontains 1) { throw "VNC: requiere autenticacion (tipos: $($types -join ','))" }
        $s.WriteByte(1)
        if ((To-U32 (Read-Exact $s 4) 0) -ne 0) { throw 'VNC: SecurityResult fallido' }
    } else {
        if ((To-U32 (Read-Exact $s 4) 0) -ne 1) { throw 'VNC: requiere autenticacion' }
    }
    $s.WriteByte(1)                                   # ClientInit shared
    $init = Read-Exact $s 24
    $w = To-U16 $init 0; $h = To-U16 $init 2
    $nameLen = To-U32 $init 20; if ($nameLen) { [void](Read-Exact $s $nameLen) }

    # Pedimos 32bpp little-endian BGRX (true colour, shifts R16 G8 B0)
    $pf = [byte[]](0,0,0,0, 32,24,0,1, 0,255, 0,255, 0,255, 16,8,0, 0,0,0)
    $s.Write($pf, 0, $pf.Length)
    $enc = [byte[]](2,0, 0,1, 0,0,0,0)               # SetEncodings: solo Raw
    $s.Write($enc, 0, $enc.Length)
    $req = [byte[]](3,0, 0,0, 0,0, [byte]($w -shr 8),[byte]($w -band 255), [byte]($h -shr 8),[byte]($h -band 255))
    $s.Write($req, 0, $req.Length)

    $bmp = New-Object Drawing.Bitmap($w, $h, [Drawing.Imaging.PixelFormat]::Format32bppRgb)
    $got = $false
    while (-not $got) {
        $type = (Read-Exact $s 1)[0]
        if ($type -ne 0) { throw "VNC: mensaje inesperado $type" }
        $hdr = Read-Exact $s 3
        $rects = To-U16 $hdr 1
        for ($r = 0; $r -lt $rects; $r++) {
            $rh = Read-Exact $s 12
            $x = To-U16 $rh 0; $y = To-U16 $rh 2; $rw = To-U16 $rh 4; $rht = To-U16 $rh 6
            $encoding = To-U32 $rh 8
            if ($encoding -ne 0) { continue }
            $data = Read-Exact $s ($rw * $rht * 4)
            $lock = $bmp.LockBits((New-Object Drawing.Rectangle($x, $y, $rw, $rht)), [Drawing.Imaging.ImageLockMode]::WriteOnly, $bmp.PixelFormat)
            for ($row = 0; $row -lt $rht; $row++) {
                [Runtime.InteropServices.Marshal]::Copy($data, $row * $rw * 4, [IntPtr]($lock.Scan0.ToInt64() + $row * $lock.Stride), $rw * 4)
            }
            $bmp.UnlockBits($lock)
        }
        $got = $true
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $OutFile) | Out-Null
    $bmp.Save($OutFile, [Drawing.Imaging.ImageFormat]::Png)
    Write-Output $OutFile
} finally {
    $tcp.Close()
}
