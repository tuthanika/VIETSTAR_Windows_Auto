param(
    [string]$Mode,
    [object]$Input
)

Write-Host "[DEBUG] Upload received Input type=$($Input.GetType().FullName)"
Write-Host "=== Upload start for $Mode ==="
# Nếu Input là PSObject (đọc từ JSON), chuyển sang hashtable
$buildResult = @{}
$props = $Input | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
foreach ($p in $props) { $buildResult[$p] = $Input.$p }

Write-Host "[DEBUG] Coerced buildResult keys=$($buildResult.Keys -join ', ')"

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
