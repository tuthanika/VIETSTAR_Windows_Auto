# ENV
$ua = [Environment]::GetEnvironmentVariable("FORUM_UA")
if ([string]::IsNullOrWhiteSpace($ua)) {
  $ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36"
}
$cookieHeader = [Environment]::GetEnvironmentVariable("FORUM_COOKIE")
if ([string]::IsNullOrWhiteSpace($cookieHeader)) { Write-Host "ERROR: FORUM_COOKIE env empty"; exit 1 }

# Read rules
$rulesRaw = [Environment]::GetEnvironmentVariable("FILE_CODE_RULES")
$rules = @()
if (-not [string]::IsNullOrWhiteSpace($rulesRaw)) { try { $rules = $rulesRaw | ConvertFrom-Json } catch {} }

function Resolve-Folder {
  param([string]$FileNameA)
  $folder = "Auto"
  foreach ($r in $rules) {
    if ($FileNameA.ToLower() -like $r.Pattern.ToLower()) { $folder = $r.Folder; break }
  }
  Write-Host "DEBUG: matched folder=[$folder] for filenameA=[$FileNameA]"
  return $folder
}

# Pipe
$pipePath = (Join-Path $env:SCRIPT_PATH "links.final.txt")
Remove-Item $pipePath -ErrorAction Ignore

# Input
$listPath = (Join-Path $env:REPO_PATH "link.txt")
if (-not (Test-Path $listPath)) { Write-Host "WARN: link.txt not found"; exit 0 }
$links = Get-Content $listPath | Where-Object { $_.Trim().Length -gt 0 }

foreach ($link in $links) {
  Write-Host "DEBUG: Processing link=[$link]"
  $realLink  = ""
  $filenameA = ""

  if ($link -like "https://forum.rg-adguard.net/forums/*") {
    Write-Host "DEBUG: Forum section detected"
    $html = Invoke-WebRequest $link -Headers @{ Cookie = $cookieHeader } -UserAgent $ua
    Write-Host "DEBUG: section page length=$($html.Content.Length)"

    # Tìm thread trong section
    $threads = $html.Links | Where-Object { $_.href -like "/threads/*" }
    Write-Host "DEBUG: Found $($threads.Count) threads in section"
    $thread = $threads | Where-Object { $_.href -match "\.\d+/?$" } | Select-Object -First 1
    if (-not $thread) { Write-Host "WARN: No thread in section"; continue }

    $threadUrl = "https://forum.rg-adguard.net$($thread.href)"
    Write-Host "DEBUG: threadUrl=[$threadUrl]"

    $page = Invoke-WebRequest $threadUrl -Headers @{ Cookie = $cookieHeader } -UserAgent $ua
    Write-Host "DEBUG: thread page length=$($page.Content.Length)"
    if ($page.Content -match "tuthanika") { Write-Host "DEBUG: Login OK" } else { Write-Host "WARN: Login failed"; continue }

    $goMatches = [regex]::Matches($page.Content, 'https://go\.rg-adguard\.net/[^\s"<>]+')
    if ($goMatches.Count -lt 1) { Write-Host "WARN: No goLink found"; continue }
    $goLink = $goMatches[0].Value
    Write-Host "DEBUG: goLink=[$goLink]"

    $resp      = Invoke-WebRequest $goLink -MaximumRedirection 0 -ErrorAction SilentlyContinue -UserAgent $ua
    $shareLink = $resp.Headers["Location"]
    Write-Host "DEBUG: shareLink=[$shareLink]"
    if ([string]::IsNullOrWhiteSpace($shareLink)) { Write-Host "WARN: shareLink empty"; continue }

    $realLink  = (& php (Join-Path $env:REPO_PATH "downloader.php") $shareLink | Out-String).Trim()
    Write-Host "DEBUG: downloader output=[$realLink]"

    # filenameA từ slug thread
    $slugRaw   = ($thread.href.TrimEnd('/') -split '/')[2]
    $filenameA = ($slugRaw -replace "\.\d+$","") + ".iso"
  }
  elseif ($link -like "https://forum.rg-adguard.net/threads/*") {
    Write-Host "DEBUG: Forum thread detected"
    $page = Invoke-WebRequest $link -Headers @{ Cookie = $cookieHeader } -UserAgent $ua
    Write-Host "DEBUG: thread page length=$($page.Content.Length)"
    if ($page.Content -match "tuthanika") { Write-Host "DEBUG: Login OK" } else { Write-Host "WARN: Login failed"; continue }

    $goMatches = [regex]::Matches($page.Content, 'https://go\.rg-adguard\.net/[^\s"<>]+')
    if ($goMatches.Count -lt 1) { Write-Host "WARN: No goLink found"; continue }
    $goLink = $goMatches[0].Value
    Write-Host "DEBUG: goLink=[$goLink]"

    $resp      = Invoke-WebRequest $goLink -MaximumRedirection 0 -ErrorAction SilentlyContinue -UserAgent $ua
    $shareLink = $resp.Headers["Location"]
    Write-Host "DEBUG: shareLink=[$shareLink]"
    if ([string]::IsNullOrWhiteSpace($shareLink)) { Write-Host "WARN: shareLink empty"; continue }

    $realLink  = (& php (Join-Path $env:REPO_PATH "downloader.php") $shareLink | Out-String).Trim()
    Write-Host "DEBUG: downloader output=[$realLink]"

    $slugRaw   = ($link.TrimEnd('/') -split '/')[2]
    $filenameA = ($slugRaw -replace "\.\d+$","") + ".iso"
  }
  elseif ($link -like "https://cloud.mail.ru/*") {
    Write-Host "DEBUG: Cloud link"
    $realLink  = (& php (Join-Path $env:REPO_PATH "downloader.php") $link | Out-String).Trim()
    Write-Host "DEBUG: downloader output=[$realLink]"
    $filenameA = [System.IO.Path]::GetFileName($realLink)
    if (-not ($filenameA -match '\.iso$')) { $filenameA = "$filenameA.iso" }
  }
  else {
    Write-Host "WARN: Unknown link type"; continue
  }

  if (-not $realLink -or -not ($realLink -match '^https?://')) {
    Write-Host "WARN: realLink invalid [$realLink]"; continue
  }

  $folder = Resolve-Folder -FileNameA $filenameA

  # Gọi check-exists theo schema cũ
  $RawJson = (& (Join-Path $env:REPO_PATH "check-exists.ps1") -Mode "auto" -FileNameA $filenameA -Folder $folder | Out-String).Trim()
  Write-Host "DEBUG: check-exists raw=[$RawJson]"
  if (-not ($RawJson.StartsWith("{"))) { Write-Host "WARN: check-exists no JSON"; continue }

  $Info = $RawJson | ConvertFrom-Json
  Write-Host "DEBUG: Parsed → status=[$($Info.status)], key_date=[$($Info.key_date)], filenameB=[$($Info.filenameB)], folder=[$($Info.folder)], delete=[$($Info.filenameB_delete)]"

  # Pipe: status|realLink|folder|filenameA|filenameB|key_date|filenameB_delete
  $pipeLine = "$($Info.status)|$realLink|$folder|$filenameA|$($Info.filenameB)|$($Info.key_date)|$($Info.filenameB_delete)"
  Add-Content $pipePath $pipeLine
  Write-Host "DEBUG: Write pipe=[$pipeLine]"
}
