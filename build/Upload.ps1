param(
    [string]$Mode,
    [hashtable]$Input
)

Write-Host "=== Upload start for $Mode ==="

# Gọi Build và nhận hashtable
$buildResult = & "$env:SCRIPT_PATH\build\Build.ps1" -Mode $Mode -Input $Input
if ($buildResult -isnot [hashtable]) {
    Write-Warning "[WARN] Build.ps1 did not return a hashtable"
    Write-Output @{ Mode = $Mode; Status = "Skipped (invalid build output)" }
    return
}

$buildPath = $buildResult.BuildPath
if (-not $buildPath -or -not (Test-Path $buildPath)) {
    Write-Warning "[WARN] Build path not found: $buildPath"
    Write-Output @{ Mode = $Mode; Status = "Skipped (no build output)" }
    return
}

Write-Host "[DEBUG] Looking for ISO in: $buildPath"

# Lấy file ISO mới nhất trong thư mục vietstar
$isoFile = Get-ChildItem -Path $buildPath -Filter *.iso -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $isoFile) {
    Write-Warning "[WARN] No ISO found in $buildPath"
    Write-Output @{ Mode = $Mode; Status = "Skipped (no ISO)" }
    return
}

Write-Host "[DEBUG] Found ISO: $($isoFile.FullName) Size=$($isoFile.Length) bytes"
Write-Host "[DEBUG] RCLONE_CONFIG_PATH=$env:RCLONE_CONFIG_PATH"

# Upload ISO duy nhất
$uploadOut = & "$env:SCRIPT_PATH\rclone.exe" copy "$($isoFile.FullName)" "remote:$Mode" `
    --config "$env:RCLONE_CONFIG_PATH" 2>&1

Write-Host "=== DEBUG: rclone upload output ==="
Write-Host $uploadOut

# Xoá ISO sau khi upload
try {
    Write-Host "[DEBUG] Cleanup ISO: $($isoFile.FullName)"
    Remove-Item -Path $isoFile.FullName -Force -ErrorAction SilentlyContinue
} catch {
    Write-Warning "[WARN] Cleanup failed: $($_.Exception.Message)"
}

Write-Output @{
    Mode   = $Mode
    Status = "ISO uploaded and deleted"
}
