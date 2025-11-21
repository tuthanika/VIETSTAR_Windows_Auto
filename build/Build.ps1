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

# Đọc rule để lấy VietstarFolder nếu có
$rules = $env:FILE_CODE_RULES | ConvertFrom-Json
$rule  = $rules | Where-Object { $_.Mode -eq $Mode } | Select-Object -First 1
if ($rule) {
    $vsFolder  = if ($rule.VietstarFolder) { $rule.VietstarFolder } else { $rule.Folder }
    $env:vietstar = Join-Path $env:SCRIPT_PATH "$($env:vietstar_path)\$vsFolder"
	$isoFolder = if ($rule.isoFolder) { $rule.isoFolder } else { $rule.Folder }
    $env:iso = Join-Path $env:SCRIPT_PATH "$($env:iso_path)\$isoFolder"
    Write-Host "[DEBUG] ISO local path set to $env:iso"
	Write-Host "[DEBUG] Vietstar local path set to $env:vietstar"
}

Write-Host "[DEBUG] Env for CMD:"
"vietstar=$env:vietstar","silent=$env:silent","oem=$env:oem","dll=$env:dll",
"driver=$env:driver","iso=$env:iso","boot7=$env:boot7" | ForEach-Object { Write-Host "  $_" }
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

$buildOut = $env:vietstar
Write-Host "[DEBUG] Expected ISO output folder (vietstar): $env:vietstar"

$isoFile = Get-ChildItem -Path $buildOut -Filter *.iso -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Status = if ($isoFile) { "ISO ready" } else { "No ISO" }
Write-Host "[DEBUG] Status: isoFile"
Write-Host "[DEBUG] Status: $Status"

$info = @{
    Mode      = $Mode
    BuildPath = $env:vietstar
    Status    = $Status
}
$outFile = Join-Path $env:SCRIPT_PATH "build_result_$Mode.json"
$info | ConvertTo-Json | Set-Content -Path $outFile -Encoding UTF8
Write-Host "[DEBUG] Build wrote result file: $outFile"
