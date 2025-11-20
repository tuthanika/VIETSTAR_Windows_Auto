param(
    [string]$Mode,
    [object]$Input
)

Write-Host "=== Upload start for $Mode ==="

# Chuẩn hóa Input thành hashtable, tránh lỗi binding khi Main truyền ArrayList
$buildResult = $null
if ($Input -is [hashtable]) {
    $buildResult = $Input
} elseif ($Input -is [System.Collections.IDictionary]) {
    $buildResult = @{}
    foreach ($k in $Input.Keys) { $buildResult[$k] = $Input[$k] }
} elseif ($Input -is [System.Collections.IEnumerable]) {
    $buildResult = ($Input | Where-Object { $_ -is [hashtable] } | Select-Object -Last 1)
}

if (-not $buildResult) {
    Write-Warning "[WARN] Upload received no hashtable input"
    return @{
        Mode   = $Mode
        Status = "Skipped (invalid input)"
    }
}

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

# Lấy ISO mới nhất
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

# Xóa ISO sau upload
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
