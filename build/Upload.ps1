param([string]$Mode)

Write-Host "=== Upload start for $Mode ==="

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

if ([string]::IsNullOrWhiteSpace($env:RCLONE_PATH)) {
    Write-Warning "[WARN] RCLONE_PATH not set in env"
    return @{ Mode = $Mode; Status = "Skipped (no RCLONE_PATH)" }
}

$rules = $env:FILE_CODE_RULES | ConvertFrom-Json
$rule  = $rules | Where-Object { $_.Mode -eq $Mode } | Select-Object -First 1
if (-not $rule) {
    Write-Warning "[WARN] Rule for mode '$Mode' not found"
    return @{ Mode = $Mode; Status = "Skipped (no rule for mode)" }
}

$folder   = if ([string]::IsNullOrWhiteSpace($rule.Folder)) { $Mode } else { $rule.Folder }
$vsFolder = if ($rule.VietstarFolder) { $rule.VietstarFolder } else { $folder }
Write-Host "[DEBUG] Vietstar folder for mode=$Mode is '$vsFolder'"

# Local path lấy từ BuildPath (đã set đúng ở Build)
$isoFile = Get-ChildItem -Path $br.BuildPath -Filter *.iso -File |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $isoFile) {
    return @{ Mode = $Mode; Status = "Skipped (no ISO file)" }
}

Write-Host "[DEBUG] Uploading ISO: $($isoFile.FullName)"

$remoteRoot = "$env:RCLONE_PATH$env:vietstar_path"
$remoteDest = "$remoteRoot/$vsFolder"
$remoteOld  = "$remoteDest/old"

# Flags cho rclone
$flags = $env:rclone_flag -split '\s+'

# Đọc MAX_FILE từ env
[int]$MAX_FILE = if ($env:MAX_FILE) { [int]$env:MAX_FILE } else { 5 }
Write-Host "[DEBUG] MAX_FILE=$MAX_FILE"

# Patterns từ rule (dùng cho cả move và prune)
$patterns = if ($rule.Patterns) { ($rule.Patterns -join ";") } else { "" }
Write-Host "[DEBUG] Patterns for pruning/move='$patterns'"

# Liệt kê file hiện có khớp patterns ở đích
$files = @()
try {
    $jsonOut = & "$env:SCRIPT_PATH\rclone.exe" lsjson $remoteDest `
        --config "$env:RCLONE_CONFIG_PATH" `
        --include "$patterns" 2>&1
    $entries = $jsonOut | ConvertFrom-Json
    $files = @($entries | Where-Object { $_.IsDir -eq $false })
} catch {
    Write-Warning "[WARN] rclone lsjson failed at dest: $($_.Exception.Message)"
}

# Move CHỈ những file khớp patterns sang old
if ($files.Count -gt 0) {
    Write-Host "[DEBUG] Found $($files.Count) existing file(s) matching patterns at dest"
    foreach ($f in $files) {
        Write-Host "[DEBUG] Move old-matching file: $($f.Name) -> $remoteOld"
        & "$env:SCRIPT_PATH\rclone.exe" move "$remoteDest/$($f.Name)" "$remoteOld" `
            --config "$env:RCLONE_CONFIG_PATH" @flags
    }
} else {
    Write-Host "[DEBUG] No existing matching files to move."
}

# Prune trong 'old': CHỈ xét những file khớp patterns, giữ lại mới nhất MAX_FILE và xóa phần vượt
try {
    $jsonOld = & "$env:SCRIPT_PATH\rclone.exe" lsjson $remoteOld `
        --config "$env:RCLONE_CONFIG_PATH" `
        --include "$patterns" 2>&1
    $entriesOld = $jsonOld | ConvertFrom-Json
    $oldMatching = @($entriesOld | Where-Object { $_.IsDir -eq $false } | Sort-Object ModTime -Descending)

    Write-Host "[DEBUG] Old matching count=$($oldMatching.Count), keep MAX_FILE=$MAX_FILE"
    if ($oldMatching.Count -gt $MAX_FILE) {
        $toDelete = $oldMatching | Select-Object -Skip $MAX_FILE
        foreach ($del in $toDelete) {
            Write-Host "[DEBUG] Delete old-matching file: $($del.Name)"
            & "$env:SCRIPT_PATH\rclone.exe" delete "$remoteOld/$($del.Name)" `
                --config "$env:RCLONE_CONFIG_PATH" @flags
        }
    }
} catch {
    Write-Warning "[WARN] rclone lsjson failed at old: $($_.Exception.Message)"
}

# Upload ISO mới
Write-Host "[DEBUG] Uploading ISO to $remoteDest"
& "$env:SCRIPT_PATH\rclone.exe" copy "$($isoFile.FullName)" "$remoteDest" --config "$env:RCLONE_CONFIG_PATH" @flags --progress

# Xóa ISO local sau upload
Remove-Item -Path $isoFile.FullName -Force -ErrorAction SilentlyContinue

return @{ Mode = $Mode; Status = "ISO uploaded and deleted" }
