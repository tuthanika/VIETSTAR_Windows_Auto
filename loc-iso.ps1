param(
    [string]$Mode = "auto",   # auto hoặc manual
    [string]$Key,             # manual: key chính (ví dụ: windows*10)
    [string]$Folder,          # manual: folder đích (ví dụ: Windows 10)
    [string]$FileNameA        # manual/auto: filename từ link
)

function Get-Architecture {
    param([string]$name)
    if ($name -match '(?i)(x86[_\-]?64|86\-64)') { return "" } # dual-arch
    if ($name -match '(?i)(x64|amd64|64bit)')     { return "x64" }
    elseif ($name -match '(?i)(x86|32bit)')       { return "x86" }
    elseif ($name -match '(?i)(arm64|aarch64)')   { return "arm64" }
    elseif ($name -match '(?i)(arm)')             { return "arm" }
    else                                          { return "" }
}

function Get-DateTagRaw {
    param([string]$name)
    $m = [regex]::Match($name, 'v\d{2}\.\d{2}\.\d{2}')
    if ($m.Success) { return $m.Value } else { return "" }
}

# ENV
$maxFile    = [int]([Environment]::GetEnvironmentVariable("MAX_FILE") ?? "0")
$remoteRoot = "${env:REMOTE_NAME}:${env:REMOTE_TARGET}"

$keyExtra = Get-Architecture $FileNameA
$dateA    = Get-DateTagRaw $FileNameA  # giữ nguyên 'v..'

if ($Mode -eq "manual") {
    $keyPattern = $Key.ToLower()
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
        $p = $r.Pattern.ToLower()
        if ($FileNameA.ToLower() -like $p) { $matchedRule = $r; break }
    }
    if (-not $matchedRule) {
        [pscustomobject]@{ status="no_rule"; key_date=$dateA; filenameB=$FileNameA; folder=""; filenameB_delete="" } | ConvertTo-Json -Compress
        return
    }

    $keyPattern = $matchedRule.Pattern.ToLower()
    $folderName = $matchedRule.Folder
}

# key_a: key + extra (nếu có) + date
$key_a   = if ($keyExtra) { "$keyPattern*$keyExtra*$dateA" } else { "$keyPattern*$dateA" }
$baseKey = if ($keyExtra) { "$keyPattern*$keyExtra*" } else { "$keyPattern*" }
$remoteDir = "$remoteRoot/$folderName"

# Kiểm tra thư mục chính có tồn tại
$dirExists = $false
$check = & "$env:SCRIPT_PATH\rclone.exe" lsd "$remoteDir" --config "$env:RCLONE_CONFIG_PATH" 2>$null
if ($LASTEXITCODE -eq 0) {
    $dirExists = $true
} else {
    $dirExists = $false
    # reset để không làm step fail
    $global:LASTEXITCODE = 0
}

$filesMain = @()
if ($dirExists) {
    $jsonMain = & "$env:SCRIPT_PATH\rclone.exe" lsjson "$remoteDir" --config "$env:RCLONE_CONFIG_PATH" 2>$null
    if ($LASTEXITCODE -ne 0) { $global:LASTEXITCODE = 0 } # reset nếu lsjson lỗi
    if ($jsonMain -and $jsonMain.Trim().Length -gt 0) {
        try { $filesMain = $jsonMain | ConvertFrom-Json } catch {}
    }
}

# Kiểm tra thư mục old có tồn tại
$oldDir = "$remoteDir/old"
$oldExists = $false
$checkOld = & "$env:SCRIPT_PATH\rclone.exe" lsd "$oldDir" --config "$env:RCLONE_CONFIG_PATH" 2>$null
if ($LASTEXITCODE -eq 0) {
    $oldExists = $true
} else {
    $oldExists = $false
    $global:LASTEXITCODE = 0
}

$filesOld = @()
if ($oldExists) {
    $jsonOld = & "$env:SCRIPT_PATH\rclone.exe" lsjson "$oldDir" --config "$env:RCLONE_CONFIG_PATH" 2>$null
    if ($LASTEXITCODE -ne 0) { $global:LASTEXITCODE = 0 }
    if ($jsonOld -and $jsonOld.Trim().Length -gt 0) {
        try { $filesOld = $jsonOld | ConvertFrom-Json } catch {}
    }
}


# 1) Kiểm tra tuyệt đối: nếu chính filename A đã tồn tại trong folder → exists
$exactExists = $filesMain | Where-Object { $_.Name -eq $FileNameA } | Select-Object -First 1
if ($exactExists) {
    [pscustomobject]@{ status="exists"; key_date=$dateA; filenameB=$FileNameA; folder=$folderName; filenameB_delete="" } | ConvertTo-Json -Compress
    return
}

# 2) Kiểm tra tương đối theo key_a
$mainMatches = $filesMain | Where-Object { $_.Name.ToLower() -like $key_a.ToLower() }
if ($mainMatches -and $mainMatches.Count -gt 0) {
    [pscustomobject]@{ status="exists"; key_date=$dateA; filenameB=$FileNameA; folder=$folderName; filenameB_delete="" } | ConvertTo-Json -Compress
    return
}

# 3) Không khớp → upload
$filenameB = ($filesMain | Where-Object { $_.Name.ToLower() -like $baseKey.ToLower() } |
              Sort-Object -Property ModTime -Descending |
              Select-Object -ExpandProperty Name -First 1)

# Xác định danh sách cần xóa trong old nếu có MAX_FILE
$filenameB_delete = ""
if ($maxFile -gt 0) {
    $allMatches = @()
    $allMatches += ($filesMain | Where-Object { $_.Name.ToLower() -like $baseKey.ToLower() })
    $allMatches += ($filesOld  | Where-Object { $_.Name.ToLower() -like $baseKey.ToLower() })
    $plannedCount = $allMatches.Count + 1
    $needDelete = [math]::Max(0, $plannedCount - $maxFile)
    if ($needDelete -gt 0) {
        $oldCandidates = $filesOld | Where-Object { $_.Name.ToLower() -like $baseKey.ToLower() } |
                         Sort-Object -Property ModTime
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
