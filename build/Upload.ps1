param(
    [string]$Mode
)

Write-Host "=== Upload start for $Mode ==="

# Đọc build result JSON
$outFile = Join-Path $env:SCRIPT_PATH "build_result_$Mode.json"
if (-not (Test-Path $outFile)) {
    Write-Warning "[WARN] Upload cannot find build result file for mode $Mode"
    return @{ Mode = $Mode; Status = "Skipped (no build result file)" }
}

$br = (Get-Content $outFile -Raw) | ConvertFrom-Json
if (-not $br) {
    Write-Warning "[WARN] Upload failed to parse build result for mode $Mode"
    return @{ Mode = $Mode; Status = "Skipped (invalid build result)" }
}

Write-Host "[DEBUG] Read build result: Status=$($br.Status), BuildPath=$($br.BuildPath)"

if ($br.Status -ne "ISO ready") {
    Write-Warning "[WARN] No ISO to upload for mode $Mode (Status=$($br.Status))"
    return @{ Mode = $Mode; Status = $br.Status }
}

# Lấy Folder theo mode từ FILE_CODE_RULES
if ([string]::IsNullOrWhiteSpace($env:FILE_CODE_RULES)) {
    Write-Warning "[WARN] FILE_CODE_RULES not found in env"
    return @{ Mode = $Mode; Status = "Skipped (no rules)" }
}

$rules = $env:FILE_CODE_RULES | ConvertFrom-Json
$rule = $rules | Where-Object { $_.Mode -eq $Mode } | Select-Object -First 1
if (-not $rule) {
    Write-Warning "[WARN] Rule for mode '$Mode' not found"
    return @{ Mode = $Mode; Status = "Skipped (no rule for mode)" }
}

$folder = $rule.Folder
if ([string]::IsNullOrWhiteSpace($folder)) {
    $folder = $Mode  # fallback: dùng tên mode nếu Folder trống
}
Write-Host "[DEBUG] Rule folder for mode=$Mode is '$folder'"

# Tìm ISO thực tế
$isoFile = Get-ChildItem -Path $br.BuildPath -Filter *.iso -File |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $isoFile) {
    return @{ Mode = $Mode; Status = "Skipped (no ISO file)" }
}

Write-Host "[DEBUG] Uploading ISO: $($isoFile.FullName)"

# Xác định remote path: <RCLONE_PATH>vietstar/<Folder>/
if ([string]::IsNullOrWhiteSpace($env:RCLONE_PATH)) {
    Write-Warning "[WARN] RCLONE_PATH not set in env"
    return @{ Mode = $Mode; Status = "Skipped (no RCLONE_PATH)" }
}

$remoteRoot = "$env:RCLONE_PATH$env:OK_UPLOAD"
$remoteDest = "$remoteRoot/$folder"

# Thực hiện upload
Write-Host "[DEBUG] Uploading ISO to $remoteDest"
$flags = $env:rclone_flag -split '\s+'
& "$env:SCRIPT_PATH\rclone.exe" copy "$($isoFile.FullName)" "$remoteDest" --config "$env:RCLONE_CONFIG_PATH" @flags --progress

# Xóa ISO sau upload
Remove-Item -Path $isoFile.FullName -Force -ErrorAction SilentlyContinue

return @{ Mode = $Mode; Status = "ISO uploaded and deleted" }
