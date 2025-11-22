param(
    [string]$Mode,
    [object]$Input
)

# Chuẩn hóa Input thành hashtable
$inputMap = @{}
if ($Input -is [hashtable]) { $inputMap = $Input }
elseif ($Input -is [System.Collections.IDictionary]) {
    foreach ($k in $Input.Keys) { $inputMap[$k] = $Input[$k] }
}

Write-Host "=== Build start for $Mode ==="

Write-Host "[DEBUG] Env for CMD:"
"vietstar=$env:vietstar","silent=$env:silent","oem=$env:oem","dll=$env:dll",
"driver=$env:driver","iso=$env:iso","boot7=$env:boot7" | ForEach-Object { Write-Host "  $_" }

if (-not (Test-Path -LiteralPath $env:vietstar)) {
    New-Item -ItemType Directory -Force -Path $env:vietstar | Out-Null
    Write-Host "[DEBUG] Created vietstar output dir: $env:vietstar"
}

# Build must call file.cmd mode
$cmdFile = Join-Path $env:SCRIPT_PATH "zzz.Windows-imdisk.cmd"
if (-not (Test-Path $cmdFile)) {
    Write-Error "[ERROR] Build script not found: $cmdFile"
    exit 1
}

Write-Host "[DEBUG] Calling: $cmdFile $Mode"
Start-Process -FilePath $cmdFile -ArgumentList $Mode -NoNewWindow -Wait
$exitCode = $LASTEXITCODE
Write-Host "[DEBUG] Exit code=$exitCode"

if ($exitCode -ne 0) {
    Write-Warning "[WARN] zzz.Windows-imdisk.cmd returned non-zero exit code ($exitCode)"
}

Write-Host "[DEBUG] Expected ISO output folder (vietstar): $env:vietstar"

$isoFile = Get-ChildItem -Path $env:vietstar -Filter *.iso -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Status = if ($isoFile) { "ISO ready" } else { "No ISO" }

Write-Host "[DEBUG] Status: $Status"

$info = @{
    Mode      = $Mode
    BuildPath = $env:vietstar
    Status    = $Status
}
$outFile = Join-Path $env:SCRIPT_PATH "build_result_$Mode.json"
$info | ConvertTo-Json | Set-Content -Path $outFile -Encoding UTF8
Write-Host "[DEBUG] Build wrote result file: $outFile"
