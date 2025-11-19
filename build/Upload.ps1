param(
    [string]$Mode,
    [hashtable]$Input
)

Write-Host "=== Upload start for $Mode ==="

$buildPath = $Input.BuildPath
Write-Host "[DEBUG] BuildPath=$buildPath"
if (-not (Test-Path $buildPath)) {
    Write-Warning "[WARN] Build path not found: $buildPath"
    Write-Output @{ Mode = $Mode; Status = "Skipped (no build output)" }
    return
}

Write-Host "[DEBUG] Uploading with rclone"
Write-Host "[DEBUG] RCLONE_CONFIG_PATH=$env:RCLONE_CONFIG_PATH"

$uploadOut = & "$env:SCRIPT_PATH\rclone.exe" copy "$buildPath" "remote:$Mode" `
    --config "$env:RCLONE_CONFIG_PATH" 2>&1

Write-Host "=== DEBUG: rclone upload output ==="
Write-Host $uploadOut

# Optional cleanup after upload
try {
    Write-Host "[DEBUG] Cleanup: $buildPath"
    Remove-Item -Path "$buildPath" -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Write-Warning "[WARN] Cleanup failed: $($_.Exception.Message)"
}

Write-Output @{
    Mode = $Mode
    Status = "Uploaded and cleaned"
}
