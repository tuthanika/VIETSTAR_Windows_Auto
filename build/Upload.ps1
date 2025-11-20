param(
    [string]$Mode,
    [object]$Input
)

Write-Host "=== Upload start for $Mode ==="

# Chuẩn hóa input thành hashtable
$buildResult = $null
if ($Input -is [hashtable]) { $buildResult = $Input }
elseif ($Input -is [System.Collections.IEnumerable]) {
    $buildResult = ($Input | Where-Object { $_ -is [hashtable] } | Select-Object -Last 1)
}

if (-not $buildResult) {
    Write-Warning "[WARN] Upload received no hashtable input"
    return @{ Mode = $Mode; Status = "Skipped (invalid input)" }
}

if ($buildResult.Status -ne "ISO ready") {
    Write-Warning "[WARN] No ISO to upload for mode $Mode"
    return @{ Mode = $Mode; Status = $buildResult.Status }
}

# Lấy ISO thực tế
$isoFile = Get-ChildItem -Path $buildResult.BuildPath -Filter *.iso -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $isoFile) {
    return @{ Mode = $Mode; Status = "Skipped (no ISO file)" }
}

Write-Host "[DEBUG] Uploading ISO: $($isoFile.FullName)"
$uploadOut = & "$env:SCRIPT_PATH\rclone.exe" copy "$($isoFile.FullName)" "remote:$Mode" --config "$env:RCLONE_CONFIG_PATH" 2>&1
Write-Host $uploadOut

# Xóa ISO sau upload
Remove-Item -Path $isoFile.FullName -Force -ErrorAction SilentlyContinue

return @{ Mode = $Mode; Status = "ISO uploaded and deleted" }
