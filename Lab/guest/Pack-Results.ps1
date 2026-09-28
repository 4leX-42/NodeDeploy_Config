<#
    Se ejecuta DENTRO de la VM: copia los resultados de NodeDeploy a una carpeta y la comprime en C:\LabRun\<Tag>.zip.
    Se copia antes de comprimir: Compress-Archive falla si algun log sigue abierto.
#>
param([string]$Tag = 'results')
$Tag = $Tag.Trim()   # vmrun/cmd dejan un espacio al final del ultimo argumento
$run = 'C:\LabRun'; $root = 'C:\nodedeploy\NodeDeploy_Run'
$pack = Join-Path $run ("pack_{0}_{1}" -f $Tag, (Get-Date -Format 'HHmmss'))
New-Item -ItemType Directory -Force -Path "$pack\logs" | Out-Null
foreach ($f in "$run\deploybat_result.txt", "$run\deploybat_console.txt", "$run\Run-DeployBat.out.log", "$root\POSTVALIDATE_REPORT.md", "$root\Validate_Report.md") {
    if (Test-Path $f) { Copy-Item -LiteralPath $f -Destination $pack -Force -ErrorAction SilentlyContinue }
}
Get-ChildItem "$root\state\logs" -File -ErrorAction SilentlyContinue | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination "$pack\logs" -Force -ErrorAction SilentlyContinue }
Compress-Archive -Path "$pack\*" -DestinationPath "$run\$Tag.zip" -Force
exit 0
