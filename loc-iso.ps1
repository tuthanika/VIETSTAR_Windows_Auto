param(
    [string]$Mode = "auto",   # auto hoặc manual
    [string]$Key,             # manual: key chính (ví dụ: windows*10)
    [string]$Folder,          # manual: folder đích (ví dụ: Windows 10)
    [string]$FileNameA        # manual/auto: filename từ link
)

function Get-Architecture {
    param([string]$name)
    # Dual-arch → extra rỗng
    if ($name -match '(?i)(x86[_\-]?64|86\-64)') { return "" }
    if ($name -match '(?i)(x64|amd64|64bit)')     { return "x64" }
    elseif ($name -match '(?i)(x86|32bit)')       { return "x86" }
    elseif ($name -match '(?i)(arm64|aarch64)')   { return "arm64" }
    elseif ($name -match '(?i)(arm)')             { return "arm" }
    else                                          { return "" }
}

function Get-DateTagRaw {
    param([string]$name)
    # Giữ nguyên 'v' để khớp chính xác với tên file (ví dụ: v23.05.07)
    $m = [regex]::Match($name, 'v\d{2}\.\d{2}\.\d{2}')
    if ($m.Success) { return $m.Value } else { return "" }
}

# ENV
$maxFile    = [int]([Environment]::GetEnvironmentVariable("MAX_FILE") ?? "0")
$remoteRoot = "${env:REMOTE_NAME}:${env:REMOTE_TARGET}"

# Extract từ filenameA
$keyExtra = Get-Architecture $FileNameA
$dateA    = Get-DateTagRaw $FileNameA  # giữ nguyên 'v..'

# Xác định pattern key/folder
if ($Mode -eq "manual") {
    $keyPattern = $Key.ToLower()          # ví dụ: "*windows*xp*"
    $folderName = $Folder
}
else {
    $raw = [Environment]::GetEnvironmentVariable("FILE_CODE_RULES")
    if ([string]::IsNullOrWhiteSpace($raw)) {
        [pscustomobject]@{ status="no_rule"; key_date=$dateA; filenameB=$FileNameA; folder=""; filenameB_delete="" } | ConvertTo-Json -Compress
        return
    }
    try { $rules = $raw | ConvertFrom-Json } catch {
        [pscustomobject]@{ status="no_rule"; key_date=$dateA; filenameB=$FileNameA; folder=""; filenameB_delete="" } | ConvertTo-Json -Compress
        return
    }

    $matchedRule = $null
    foreach ($r in $rules) {
        $p = $r.Pattern.ToLower()  # wildcard từ ENV, ví dụ "*windows*xp*"
        if ($FileNameA.ToLower() -like $p) { $matchedRule = $r; break }
    }
    if (-not $matchedRule) {
        [pscustomobject]@{ status="no_rule"; key_date=$dateA; filenameB=$FileNameA; folder=""; filenameB_delete="" } | ConvertTo-Json -Compress
        return
    }

    $keyPattern = $matchedRule.Pattern.ToLower()
    $folderName = $matchedRule.Folder
}

# Tạo pattern tương đối: key + extra (nếu có) + date
$key_a = if ($keyExtra) { "$keyPattern*$keyExtra*$dateA" } else { "$keyPattern*$dateA" }
$remoteDir = "$remoteRoot/$folderName"

# Lấy danh sách file trong folder chính
$jsonMain = ""
try { $jsonMain = & "$env:SCRIPT_PATH\rclone.exe" lsjson "$remoteDir" --config "$env:RCLONE_CONFIG_PATH" } catch { $jsonMain = "" }
$filesMain = @()
if ($jsonMain -and $jsonMain.Trim().Length -gt 0) { try { $filesMain = $jsonMain | ConvertFrom-Json } catch {} }

# Lấy danh sách file trong old (có thể chưa tồn tại → rỗng)
$jsonOld = ""
try { $jsonOld = & "$env:SCRIPT_PATH\rclone.exe" lsjson "$remoteDir/old" --config "$env:RCLONE_CONFIG_PATH" } catch { $jsonOld = "" }
$filesOld = @()
if ($jsonOld -and $jsonOld.Trim().Length -gt 0) { try { $filesOld = $jsonOld | ConvertFrom-Json } catch {} }

# 1) Kiểm tra tuyệt đối: nếu chính filename A đã tồn tại trong folder → exists
$exactExists = $filesMain | Where-Object { $_.Name -eq $FileNameA } | Select-Object -First 1
if ($exactExists) {
    [pscustomobject]@{
        status     = "exists"
        key_date   = $dateA
        filenameB  = $FileNameA
        folder     = $folderName
        filenameB_delete = ""
    } | ConvertTo-Json -Compress
    return
}

# 2) Kiểm tra tương đối theo key_a: nếu đã có bản khớp → exists
$mainMatches = $filesMain | Where-Object { $_.Name.ToLower() -like $key_a.ToLower() }
if ($mainMatches -and $mainMatches.Count -gt 0) {
    [pscustomobject]@{
        status     = "exists"
        key_date   = $dateA
        filenameB  = $FileNameA
        folder     = $folderName
        filenameB_delete = ""
    } | ConvertTo-Json -Compress
    return
}

# 3) Không khớp → cần upload
# filenameB: bản hiện hữu để di chuyển (nếu muốn), chọn mới nhất theo ModTime
$filenameB = ($filesMain | Sort-Object -Property ModTime -Descending | Select-Object -ExpandProperty Name -First 1)

# Xác định danh sách cần xóa trong old nếu có MAX_FILE
$filenameB_delete = ""
if ($maxFile -gt 0) {
    $allMatches = @()
    $allMatches += $filesMain
    $allMatches += $filesOld
    $plannedCount = $allMatches.Count + 1
    $needDelete = [math]::Max(0, $plannedCount - $maxFile)
    if ($needDelete -gt 0) {
        $oldCandidates = $filesOld | Sort-Object -Property ModTime -Ascending
        $toDel = $oldCandidates | Select-Object -First $needDelete | Select-Object -ExpandProperty Name
        if ($toDel) { $filenameB_delete = ($toDel -join "|") }
    }
}

[pscustomobject]@{
    status     = "upload"
    key_date   = $dateA
    filenameB  = $filenameB
    folder     = $folderName
    filenameB_delete = $filenameB_delete
} | ConvertTo-Json -Compress
