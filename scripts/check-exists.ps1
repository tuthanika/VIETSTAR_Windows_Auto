param(
    [string]$Mode = "auto",   # auto hoặc manual
    [string]$Key,
    [string]$Folder,
    [string]$FileNameA
)

$ErrorActionPreference = 'Stop'

function Get-Architecture {
    param([string]$name)
    if ($name -match '(?i)(x86[_\-]?64|86\-64)') { return "" }
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
$dateA    = Get-DateTagRaw $FileNameA

# Resolve rule
if ($Mode -eq "manual") {
    $keyPattern = $Key.ToLower()
    $folderName = $Folder
}
else {
    $raw = [Environment]::GetEnvironmentVariable("FILE_CODE_RULES")
    try { $rules = $raw | ConvertFrom-Json } catch { $rules = @() }
    $matchedRule = $null
    foreach ($r in $rules) {
        foreach ($pat in $r.Patterns) {
            if ($FileNameA.ToLower() -like $pat.ToLower()) { $matchedRule = $r; break }
        }
        if ($matchedRule) { break }
    }
    if (-not $matchedRule) {
        [pscustomobject]@{ status="no_rule"; key_date=$dateA; filenameB=$FileNameA; folder=""; filenameB_delete="" } | ConvertTo-Json -Compress
        exit 0
    }
    $keyPattern = ($matchedRule.Patterns[0]).ToLower()
    $folderName = $matchedRule.Folder
}

# key patterns
$key_a   = if ($keyExtra) { "$keyPattern*$keyExtra*$dateA" } else { "$keyPattern*$dateA" }
$baseKey = if ($keyExtra) { "$keyPattern*$keyExtra*" } else { "$keyPattern*" }

$remoteDir = "$remoteRoot/$folderName"
$oldDir    = "$remoteDir/old"

# List files
$filesMain = @()
$filesOld  = @()
try {
    $jsonMain = & "$env:SCRIPT_PATH\rclone.exe" lsjson "$remoteDir" --config "$env:RCLONE_CONFIG_PATH" 2>$null
    if ($jsonMain) { $filesMain = $jsonMain | ConvertFrom-Json }
} catch {}
try {
    $jsonOld = & "$env:SCRIPT_PATH\rclone.exe" lsjson "$oldDir" --config "$env:RCLONE_CONFIG_PATH" 2>$null
    if ($jsonOld) { $filesOld = $jsonOld | ConvertFrom-Json }
} catch {}

# Check exists
$exactExists = $filesMain | Where-Object { $_.Name -eq $FileNameA } | Select-Object -First 1
if ($exactExists) {
    [pscustomobject]@{ status="exists"; key_date=$dateA; filenameB=$FileNameA; folder=$folderName; filenameB_delete="" } | ConvertTo-Json -Compress
    exit 0
}

$mainMatchesToday = $filesMain | Where-Object { $_.Name.ToLower() -like $key_a.ToLower() }
if ($mainMatchesToday.Count -gt 0) {
    [pscustomobject]@{ status="exists"; key_date=$dateA; filenameB=$FileNameA; folder=$folderName; filenameB_delete="" } | ConvertTo-Json -Compress
    exit 0
}

# Prepare upload
$filenameB = ($filesMain | Where-Object { $_.Name.ToLower() -like $baseKey.ToLower() } |
              Sort-Object -Property ModTime -Descending |
              Select-Object -ExpandProperty Name -First 1)

$filenameB_delete = ""
if ($maxFile -gt 0) {
    # Gom tất cả file matching từ cả main và old
    $allMatches = @()
    $allMatches += ($filesMain | Where-Object { $_.Name.ToLower() -like $baseKey.ToLower() })
    $allMatches += ($filesOld  | Where-Object { $_.Name.ToLower() -like $baseKey.ToLower() })

    # Sort theo thời gian mới nhất trước
    $sortedMatches = $allMatches | Sort-Object -Property ModTime -Descending

    # Nếu số lượng vượt quá MAX_FILE thì chọn phần dư để xóa
    if ($sortedMatches.Count -gt $maxFile) {
        $toDelete = $sortedMatches | Select-Object -Skip $maxFile | Select-Object -ExpandProperty Name
        if ($toDelete) { $filenameB_delete = ($toDelete -join "|") }
    }
}

[pscustomobject]@{
    status           = "upload"
    key_date         = $dateA
    filenameB        = $filenameB
    folder           = $folderName
    filenameB_delete = $filenameB_delete
} | ConvertTo-Json -Compress
