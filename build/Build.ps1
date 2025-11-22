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
    $env:vietstar = Join-Path (Join-Path $env:SCRIPT_PATH $env:vietstar_path) $vsFolder
	$isoFolder = if ($rule.isoFolder) { $rule.isoFolder } else { $rule.Folder }
    $env:iso      = Join-Path (Join-Path $env:SCRIPT_PATH $env:iso_path) $isoFolder
    Write-Host "[DEBUG] ISO local path set to $env:iso"
	Write-Host "[DEBUG] Vietstar local path set to $env:vietstar"
}


Write-Host "[DEBUG] Env for CMD:"
"vietstar=$env:vietstar","silent=$env:silent","oem=$env:oem","dll=$env:dll",
"driver=$env:driver","iso=$env:iso","boot7=$env:boot7" | ForEach-Object { Write-Host "  $_" }

if (-not (Test-Path -LiteralPath $env:vietstar)) {
    New-Item -ItemType Directory -Force -Path $env:vietstar | Out-Null
    Write-Host "[DEBUG] Created vietstar output dir: $env:vietstar"
}
$isFile1 = Get-ChildItem "D:\RUN\z.ISO"
$isFile2 = Get-ChildItem "$env:iso"
Write-Host "[DEBUG] Status: $isFile1"
Write-Host "[DEBUG] Status: $isFile2"
$vsFile1 = Get-ChildItem "D:\RUN\z.VIETSTAR"
$vsFile2 = Get-ChildItem "D:\RUN\z.VIETSTAR\Windows 7"
Write-Host "[DEBUG] Status: $vsFile1"
Write-Host "[DEBUG] Status: $vsFile2"

# Build must call file.cmd mode
$cmdFile = Join-Path $env:SCRIPT_PATH "zzz.Windows-imdisk.cmd"
if (-not (Test-Path $cmdFile)) {
    Write-Error "[ERROR] Build script not found: $cmdFile"
    exit 1
}

# 1) Log ngay trước khi gọi CMD
Write-Host "[DEBUG] Pre-CMD env:"
Write-Host "iso=$env:iso"
Write-Host "vietstar=$env:vietstar"

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
$isoFile1 = Get-ChildItem "D:\RUN\z.ISO\Windows 7\1"
$isoFile2 = Get-ChildItem "D:\RUN\z.VIETSTAR\Windows 7\1"


Write-Host "[DEBUG] Status: $isoFile"
Write-Host "[DEBUG] Status: $isoFile1"
Write-Host "[DEBUG] Status: $isoFile2"
Write-Host "[DEBUG] Status: $Status"

$info = @{
    Mode      = $Mode
    BuildPath = $env:vietstar
    Status    = $Status
}
$outFile = Join-Path $env:SCRIPT_PATH "build_result_$Mode.json"
$info | ConvertTo-Json | Set-Content -Path $outFile -Encoding UTF8
Write-Host "[DEBUG] Build wrote result file: $outFile"
