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

# Chuẩn hoá patterns: rclone chấp nhận nhiều mẫu khi nối bằng ';'
$patterns = if ($rule.Patterns) { ($rule.Patterns -join ";") } else { "" }
Write-Host "[DEBUG] Patterns for pruning/move='$patterns'"

# Bảo đảm thư mục old tồn tại
& "$env:SCRIPT_PATH\rclone.exe" mkdir "$remoteOld" --config "$env:RCLONE_CONFIG_PATH" @flags | Out-Null

function Get-RcloneFiles {
    param([string]$remotePath,[string]$includePatterns)
    try {
        $args = @("lsjson", $remotePath, "--config", "$env:RCLONE_CONFIG_PATH")
        if ($includePatterns -and $includePatterns.Trim() -ne "") {
            $args += @("--include", $includePatterns)
        }
        $json = & "$env:SCRIPT_PATH\rclone.exe" @args 2>&1
        $entries = $json | ConvertFrom-Json
        return @($entries | Where-Object { $_.IsDir -eq $false })
    } catch {
        Write-Warning "[WARN] rclone lsjson failed at remotePath: $($_.Exception.Message)"
        return @()
    }
}

# B1: Move file khớp từ dest sang old
$destMatching = Get-RcloneFiles -remotePath $remoteDest -includePatterns $patterns
if ($destMatching.Count -gt 0) {
    Write-Host "[DEBUG] Found $($destMatching.Count) matching file(s) at dest -> move to old"
    foreach ($f in $destMatching) {
        Write-Host "[DEBUG] Move: $($f.Name) -> $remoteOld"
        & "$env:SCRIPT_PATH\rclone.exe" move "$remoteDest/$($f.Name)" "$remoteOld" `
            --config "$env:RCLONE_CONFIG_PATH" @flags
    }
} else {
    Write-Host "[DEBUG] No matching files at dest to move."
}

# B2: Prune old để giữ đúng MAX_FILE
$oldMatching = Get-RcloneFiles -remotePath $remoteOld -includePatterns $patterns |
               Sort-Object ModTime -Descending
Write-Host "[DEBUG] Old matching count=$($oldMatching.Count), keep MAX_FILE=$MAX_FILE"
if ($oldMatching.Count -gt $MAX_FILE) {
    $toDelete = $oldMatching | Select-Object -Skip $MAX_FILE
    foreach ($del in $toDelete) {
        Write-Host "[DEBUG] Delete old file: $($del.Name)"
        & "$env:SCRIPT_PATH\rclone.exe" delete "$remoteOld/$($del.Name)" `
            --config "$env:RCLONE_CONFIG_PATH" @flags
    }
}

# B3: Upload ISO mới
Write-Host "[DEBUG] Uploading ISO to $remoteDest with flags: $($flags -join ' ')"
& "$env:SCRIPT_PATH\rclone.exe" copy "$($isoFile.FullName)" "$remoteDest" --config "$env:RCLONE_CONFIG_PATH" @flags --progress

# Xóa ISO local sau upload
Remove-Item -Path $isoFile.FullName -Force -ErrorAction SilentlyContinue

# B4: Ghi thông tin vào file tạm (Hỗ trợ nhiều file trong 1 lần chạy)
try {
    $buildDate = Get-Date -Format "yyyy-MM-dd"
    $timeNow   = Get-Date -Format "HH:mm:ss"
    $remoteIso = $isoFile.Name

    $localIsoDir = $env:iso
    $latestIso = Get-ChildItem -Path $localIsoDir -File -Filter *.iso |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $localIsoName = if ($latestIso) { $latestIso.Name } else { "" }

    # Tạo dòng dữ liệu cho file hiện tại
    $currentLine = "$Mode|$buildDate|$timeNow|$localIsoName|$remoteIso"

    # Ghi THÊM (Append) vào file tạm chung của Job này
    # File này nằm trong thư mục WORKSPACE của GitHub
    $tempDataFile = Join-Path $env:GITHUB_WORKSPACE "all_builds_data.txt"
    $currentLine | Out-File -FilePath $tempDataFile -Append -Encoding utf8

    Write-Host "[DEBUG] Added to temp file: $currentLine"
} catch {
    Write-Warning "[WARN] Failed to save build data: $($_.Exception.Message)"
}
return @{ Mode = $Mode; Status = "ISO uploaded and build data prepared" }