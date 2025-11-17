param(
    [Parameter(Mandatory=$true)][string]$SectionUrl,
    [string]$ThreadFilter = ""
)

$ErrorActionPreference = 'Stop'

# ENV
$ua = [Environment]::GetEnvironmentVariable("FORUM_UA")
if ([string]::IsNullOrWhiteSpace($ua)) {
  $ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
}
$cookieHeader = [Environment]::GetEnvironmentVariable("FORUM_COOKIE")
if ([string]::IsNullOrWhiteSpace($cookieHeader)) {
  Write-Host "ERROR: FORUM_COOKIE env empty"
  exit 1
}

# Helper: lấy thread id để sort (hỗ trợ .../latest)
function Get-ThreadId([string]$href) {
  if ([string]::IsNullOrWhiteSpace($href)) { return 0 }
  $norm = $href -replace '/latest/?$', ''
  $m = [regex]::Match($norm,'\.(\d+)/?$')
  if ($m.Success) { return [int]$m.Groups[1].Value } else { return 0 }
}

# Tải HTML section
$html = Invoke-WebRequest $SectionUrl -Headers @{ Cookie = $cookieHeader } -UserAgent $ua
$threads = $html.Links | Where-Object { $_.href -like "/threads/*" }
Write-Host "DEBUG: Found $($threads.Count) threads in section"

# Áp dụng filter
if (-not [string]::IsNullOrWhiteSpace($ThreadFilter)) {
  $regexPattern = "(?i)" + ($ThreadFilter -replace '\*','.*')
  $filteredThreads = $threads | Where-Object {
    $_.href -match $regexPattern -or $_.innerText -match $regexPattern
  }
} else {
  $filteredThreads = $threads | Where-Object {
    $_.href -match '(?i)en-ru' -or $_.innerText -match '(?i)en-ru'
  }
}
Write-Host "DEBUG: filteredThreads count=$($filteredThreads.Count)"

# Áp dụng rules để chọn thread mới nhất cho mỗi folder
$rulesRaw = [Environment]::GetEnvironmentVariable("FILE_CODE_RULES")
$rules = $rulesRaw | ConvertFrom-Json
$acceptedPatterns = @()  # NEW: patterns đã chiếm
$chosen = @{}
$results = @()

foreach ($r in $rules) {
  $folder   = $r.Folder
  $matches  = @()

  foreach ($pat in $r.Patterns) {
    $tmp = $filteredThreads | Where-Object { $_.href -like $pat -or $_.innerText -like $pat }
    if ($tmp.Count -gt 0) { $matches += $tmp }
  }

  # NEW: loại trừ threads khớp patterns đã chiếm bởi rule trước
  if ($acceptedPatterns.Count -gt 0) {
    $matches = $matches | Where-Object {
      $txt = ($_.href + ' ' + $_.innerText)
      $hitPrev = $false
      foreach ($p in $acceptedPatterns) {
        if ($txt -like $p) { $hitPrev = $true; break }
      }
      -not $hitPrev
    }
  }

  Write-Host "DEBUG: Rule [$folder] matched $($matches.Count) threads"
  if ($matches.Count -eq 0) { continue }

  $selected = $matches | Sort-Object @{Expression={Get-ThreadId $_.href};Descending=$true} | Select-Object -First 1
  Write-Host "DEBUG: Rule [$folder] selected thread href=[$($selected.href)]"

  if (-not $chosen.ContainsKey($selected.href)) {
    $chosen[$selected.href] = $true
    $results += @{ Folder=$folder; Href=$selected.href }

    # NEW: cập nhật patterns đã chiếm cho rule sau
    if ($r.Patterns) { $acceptedPatterns += $r.Patterns }
  } else {
    Write-Host "DEBUG: Rule [$folder] skipped because thread [$($selected.href)] already taken"
  }
}

# Output: danh sách threadUrl với folder
foreach ($res in $results) {
  $threadUrl = "https://forum.rg-adguard.net$($res.Href)"
  Write-Output "$($res.Folder)|$threadUrl"
}
