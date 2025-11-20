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

Write-Host "[DEBUG] Input keys=$($inputMap.Keys -join ', ')"
Write-Host "=== Build start for $Mode ==="
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

# BuildPath chính là thư mục vietstar – nơi ISO được tạo
$buildOut = $env:vietstar
Write-Host "[DEBUG] Expected ISO output folder (vietstar): $buildOut"

# Đảm bảo thư mục tồn tại
if (-not (Test-Path $buildOut)) {
    New-Item -ItemType Directory -Force -Path $buildOut | Out-Null
}

Write-Output @{
    Mode      = $Mode
    BuildPath = $buildOut
    ExitCode  = $exitCode
}
