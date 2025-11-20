param(
    [string]$Mode,
    [hashtable]$Input
)

Write-Host "=== Upload start for $Mode ==="

# Nhận hashtable từ Build.ps1
$buildResult = $Input
Write-Host "[DEBUG] BuildResult keys=$($buildResult.Keys -join ', ')"

$buildPath = $buildResult.BuildPath
if (-not $buildPath -or -not (Test-Path $buildPath)) {
    Write-Warning "[WARN] Build path not found: $buildPath"
    return @{
        Mode   = $Mode
        Status = "Skipped (no build output)"
    }
}

Write-Host "[DEBUG] Looking for ISO in: $buildPath"
$isoFile = Get-ChildItem -Path $buildPath -Filter *.iso -File |
           Sort-Object LastWriteTime -Descending |
           Select-Object -First 1

if (-not $isoFile) {
    Write-Warning "[WARN] No ISO found in $buildPath"
    return @{
        Mode   = $Mode
        Status = "Skipped (no ISO)"
    }
}

Write-Host "[DEBUG] Found ISO: $($isoFile.FullName) Size=$([math]::Round($isoFile.Length/1MB,2)) MB"
Write-Host "[DEBUG] RCLONE_CONFIG_PATH=$env:RCLONE_CONFIG_PATH"

# Upload ISO theo Mode
$uploadOut = & "$env:SCRIPT_PATH\rclone.exe" copy "$($isoFile.FullName)" "remote:$Mode" `
    --config "$env:RCLONE_CONFIG_PATH" 2>&1

Write-Host "=== DEBUG: rclone upload output ==="
Write-Host $uploadOut

# Xóa ISO sau khi upload
try {
    Write-Host "[DEBUG] Cleanup ISO: $($isoFile.FullName)"
    Remove-Item -Path $isoFile.FullName -Force -ErrorAction SilentlyContinue
} catch {
    Write-Warning "[WARN] Cleanup failed: $($_.Exception.Message)"
}

return @{
    Mode   = $Mode
    Status = "ISO uploaded and deleted"
}
