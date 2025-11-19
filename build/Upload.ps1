param(
    [string]$Mode,
    [hashtable]$Input
)

Write-Host "=== Upload start for $Mode ==="

# Gọi Build và lọc output thành đúng hashtable
$buildOut = @(& "$env:SCRIPT_PATH\build\Build.ps1" -Mode $Mode -Input $Input)
$buildResult = $buildOut | Where-Object { $_ -is [hashtable] } | Select-Object -Last 1
if (-not $buildResult) { $buildResult = @{} }

Write-Host "[DEBUG] BuildResult keys=$($buildResult.Keys -join ', ')"

$buildPath = $buildResult.BuildPath
if (-not $buildPath -or -not (Test-Path $buildPath)) {
    Write-Warning "[WARN] Build path not found: $buildPath"
    Write-Output @{ Mode = $Mode; Status = "Skipped (no build output)" }
    return
}

Write-Host "[DEBUG] Uploading folder: $buildPath"
Write-Host "[DEBUG] RCLONE_CONFIG_PATH=$env:RCLONE_CONFIG_PATH"

$uploadOut = & "$env:SCRIPT_PATH\rclone.exe" copy "$buildPath" "remote:$Mode" `
    --config "$env:RCLONE_CONFIG_PATH" 2>&1

Write-Host "=== DEBUG: rclone upload output ==="
Write-Host $uploadOut

# Optional cleanup
try {
    Write-Host "[DEBUG] Cleanup build output: $buildPath"
    Remove-Item -Path "$buildPath" -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Write-Warning "[WARN] Cleanup failed: $($_.Exception.Message)"
}

Write-Output @{
    Mode   = $Mode
    Status = "Uploaded and cleaned"
}
