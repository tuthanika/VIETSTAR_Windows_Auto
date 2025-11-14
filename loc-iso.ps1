param(
    [string]$Mode = "auto",   # auto hoặc manual
    [string]$Key,             # manual: key chính (ví dụ: windows*10)
    [string]$Folder,          # manual: folder đích (ví dụ: Windows 10)
    [string]$FileNameA        # manual/auto: filename từ link
)

function Get-Architecture {
    param([string]$name)

    # Nếu có cặp "x86_64"/"x86-x64"/"86-64"/"x86-64" → kiến trúc rỗng (dual-arch)
    if ($name -match '(?i)(x86[_\-]?64|86\-64)') { return "" }

    if ($name -match '(?i)(x64|amd64|64bit)')     { return "x64" }
    elseif ($name -match '(?i)(x86|32bit)')       { return "x86" }
    elseif ($name -match '(?i)(arm64|aarch64)')   { return "arm64" }
    elseif ($name -match '(?i)(arm)')             { return "arm" }
    else                                          { return "" }
}

function Get-DateTagRaw {
    param([string]$name)
    # Tìm dạng v25.11.11
    $m = [regex]::Match($name, 'v\d{2}\.\d{2}\.\d{2}')
    if ($m.Success) { return $m.Value } else { return "" }
}

function ToWildcard {
    param([string]$s)
    # Chuẩn hoá pattern sang wildcard đơn giản (lowercase, khoảng trắng -> *)
    if ([string]::IsNullOrWhiteSpace($s)) { return "" }
    return ($s.ToLower())
}

# ENV
$maxFile = [int]([Environment]::GetEnvironmentVariable("MAX_FILE") ?? "0")
$remoteRoot = "${env:REMOTE_NAME}:${env:REMOTE_TARGET}"

# Xác định key/extra/date và folder theo chế độ
$keyExtra = Get-Architecture $FileNameA
$dateRaw  = Get-DateTagRaw $FileNameA
$dateA    = if ($dateRaw) { $dateRaw.TrimStart('v') } else { "" }  # ví dụ "25.11.11"

if ($Mode -eq "manual") {
    $keyPattern = ToWildcard $Key                        # ví dụ "windows*10"
    $folderName = $Folder
}
else {
    # Auto mode: lấy từ FILE_CODE_RULES
    $raw = [Environment]::GetEnvironmentVariable("FILE_CODE_RULES")
    if ([string]::IsNullOrWhiteSpace($raw)) { return }
    try { $rules = $raw | ConvertFrom-Json } catch { return }

    $matchedRule = $null
    foreach ($r in $rules) {
        # Cho phép rule.Pattern là wildcard (ví dụ: "windows*10")
        $p = ToWildcard $r.Pattern
        if ($FileNameA.ToLower() -like $p) {
            $matchedRule = $r
            break
        }
    }
    if (-not $matchedRule) { return }

    $keyPattern = ToWildcard $matchedRule.Pattern
    $folderName = $matchedRule.Folder
}

# Tạo key_a: $key*$key.extra*$key.dateA (extra có thể rỗng)
$key_a = if ($keyExtra) { "$keyPattern*$keyExtra*$dateA" } else { "$keyPattern*$dateA" }

# Xác định đường dẫn folder trên remote (chỉ từ rule/param), KHÔNG gán date vào tên folder
$remoteDir = "$remoteRoot/$folderName"

# Lấy danh sách file trong folder và old
$jsonMain = & "$env:SCRIPT_PATH\rclone.exe" lsjson "$remoteDir" --config "$env:RCLONE_CONFIG_PATH"
$jsonOld  = & "$env:SCRIPT_PATH\rclone.exe" lsjson "$remoteDir/old" --config "$env:RCLONE_CONFIG_PATH"

$filesMain = @()
$filesOld  = @()
if ($jsonMain -and $jsonMain.Trim().Length -gt 0) { try { $filesMain = $jsonMain | ConvertFrom-Json } catch {} }
if ($jsonOld  -and $jsonOld.Trim().Length -gt 0) { try { $filesOld  = $jsonOld  | ConvertFrom-Json } catch {} }

# Kiểm tra khớp tương đối theo key_a
$mainMatches = $filesMain | Where-Object { $_.Name.ToLower() -like $key_a.ToLower() }
$oldMatches  = $filesOld  | Where-Object { $_.Name.ToLower() -like $key_a.ToLower() }

# Nếu đã có file khớp key_a trong folder → bỏ qua (không trả filenameB)
if ($mainMatches -and $mainMatches.Count -gt 0) {
    [pscustomobject]@{
        key_date   = $dateA
        filenameB  = ""               # rỗng: YAML sẽ bỏ qua
        folder     = $folderName
        filenameB_delete = ""         # không cần xoá
    } | ConvertTo-Json -Compress
    return
}

# Không khớp → cần tải/upload.
# Chọn filenameB để di chuyển (bản hiện tại trong folder cùng key chính, cùng extra nhưng khác date)
$baseKey = if ($keyExtra) { "$keyPattern*$keyExtra*" } else { "$keyPattern*" }
$filenameB = ($filesMain | Where-Object { $_.Name.ToLower() -like $baseKey.ToLower() } | Sort-Object -Property ModTime -Descending | Select-Object -ExpandProperty Name -First 1)

# Xác định danh sách cần xóa trong old nếu có MAX_FILE
$filenameB_delete = ""
if ($maxFile -gt 0) {
    # Tổng số bản cùng baseKey (không xét date) tính cả folder + old, giả định sẽ thêm file A
    $allMatches = @()
    $allMatches += ($filesMain | Where-Object { $_.Name.ToLower() -like $baseKey.ToLower() })
    $allMatches += ($filesOld  | Where-Object { $_.Name.ToLower() -like $baseKey.ToLower() })

    $plannedCount = $allMatches.Count + 1            # +1 cho file A sẽ upload
    $needDelete = [math]::Max(0, $plannedCount - $maxFile)

    if ($needDelete -gt 0) {
        # Chỉ xoá trong old, chọn các file cũ nhất theo ModTime
        $oldCandidates = $filesOld | Where-Object { $_.Name.ToLower() -like $baseKey.ToLower() } | Sort-Object -Property ModTime -Ascending
        $toDel = $oldCandidates | Select-Object -First $needDelete | Select-Object -ExpandProperty Name
        if ($toDel) { $filenameB_delete = ($toDel -join "|") }
    }
}

# Trả kết quả cho YAML
[pscustomobject]@{
    key_date   = $dateA
    filenameB  = $filenameB
    folder     = $folderName
    filenameB_delete = $filenameB_delete
} | ConvertTo-Json -Compress
