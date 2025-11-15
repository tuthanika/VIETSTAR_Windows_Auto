# ENV
$ua = [Environment]::GetEnvironmentVariable("FORUM_UA")
if ([string]::IsNullOrWhiteSpace($ua)) {
  $ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
}
$cookieHeader = [Environment]::GetEnvironmentVariable("FORUM_COOKIE")
if ([string]::IsNullOrWhiteSpace($cookieHeader)) { Write-Host "ERROR: FORUM_COOKIE env empty"; exit 1 }

# Rules from env (JSON array of { Pattern, Folder })
$rulesRaw = [Environment]::GetEnvironmentVariable("FILE_CODE_RULES")
$rules = @()
if (-not [string]::IsNullOrWhiteSpace($rulesRaw)) {
  try { $rules = $rulesRaw | ConvertFrom-Json } catch { Write-Host "ERROR: FILE_CODE_RULES invalid JSON"; exit 1 }
} else {
  Write-Host "ERROR: FILE_CODE_RULES env empty"; exit 1
}

# Resolve folder strictly via rules (no hard-coded default)
function Resolve-Folder {
  param([string]$FileNameA)

  $name = $FileNameA.ToLower()
  foreach ($r in $rules) {
    $pattern = $r.Pattern.ToLower()
    if ($name -like $pattern) {
      Write-Host "DEBUG: matched folder=[$($r.Folder)] for filenameA=[$FileNameA] via pattern=[$($r.Pattern)]"
      return $r.Folder
    }
  }

  Write-Host "WARN: no folder rule matched for filenameA=[$FileNameA]"
  return $null
}

# Redirect chain debug (manual hops)
Add-Type -AssemblyName System.Net.Http
function Resolve-FinalUrl {
  param([string]$StartUrl,[int]$MaxHops=10,[string]$UserAgent=$ua)

  $handler = New-Object System.Net.Http.HttpClientHandler
  $handler.AllowAutoRedirect = $false
  $client  = New-Object System.Net.Http.HttpClient($handler)
  $client.DefaultRequestHeaders.Clear()
  $client.DefaultRequestHeaders.Add("User-Agent",$UserAgent)

  $current = $StartUrl
  Write-Host "DEBUG: redirect-start url=[$current]"
  for ($i=1; $i -le $MaxHops; $i++) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Host "DEBUG: hop#$i request=[$current]"
    $resp = $client.GetAsync($current).Result
    $sw.Stop()
    $status = [int]$resp.StatusCode
    Write-Host "DEBUG: hop#$i status=[$status] elapsed=${($sw.ElapsedMilliseconds)}ms"
    if ($resp.Headers.Location) {
      $locAbs = if ($resp.Headers.Location.IsAbsoluteUri) { $resp.Headers.Location.AbsoluteUri } else { ([System.Uri]::new($current,$resp.Headers.Location.ToString())).AbsoluteUri }
      Write-Host "DEBUG: hop#$i Location=[$locAbs]"
      $current = $locAbs
      continue
    } else {
      Write-Host "DEBUG: hop#$i no Location → final=[$current]"
      return $current
    }
  }
  Write-Host "DEBUG: redirect-end final=[$current]"
  return $current
}

# Process downloader.php output (handles single file or folder list), strictly rule-based folder
function Process-DownloaderOutput {
  param([string]$SourceUrl,[string]$PipePath)

  $dlOutput  = (& php (Join-Path $env:REPO_PATH "downloader.php") $SourceUrl | Out-String)
  $realLines = $dlOutput.Trim() -split "`n"
  Write-Host "DEBUG: downloader lines count=[$($realLines.Count)]"

  foreach ($rl in $realLines) {
    $rl = $rl.Trim()
    if ([string]::IsNullOrWhiteSpace($rl)) { continue }
    if (-not ($rl -match '^https?://')) { Write-Host "WARN: skip non-http line"; continue }

    Write-Host "DEBUG: downloader line=[$rl]"
    $filenameA = [System.IO.Path]::GetFileName($rl)

    $folder = Resolve-Folder -FileNameA $filenameA
    if (-not $folder) { Write-Host "WARN: skip file due to no matching rule: [$filenameA]"; continue }

    $RawJson = (& (Join-Path $env:REPO_PATH "check-exists.ps1") -Mode "auto" -FileNameA $filenameA -Folder $folder | Out-String).Trim()
    Write-Host "DEBUG: check-exists raw=[$RawJson]"
    if (-not ($RawJson.StartsWith("{"))) { Write-Host "WARN: check-exists no JSON"; continue }

    $Info = $RawJson | ConvertFrom-Json
    Write-Host "DEBUG: Parsed → status=[$($Info.status)], key_date=[$($Info.key_date)], filenameB=[$($Info.filenameB)], folder=[$($Info.folder)], delete=[$($Info.filenameB_delete)]"

    $pipeLine = "$($Info.status)|$rl|$folder|$filenameA|$($Info.filenameB)|$($Info.key_date)|$($Info.filenameB_delete)"
    Add-Content $PipePath $pipeLine
    Write-Host "DEBUG: Write pipe=[$pipeLine]"
  }
}

# Pipe
$pipePath = (Join-Path $env:SCRIPT_PATH "links.final.txt")
Remove-Item $pipePath -ErrorAction Ignore

# Input
$listPath = (Join-Path $env:REPO_PATH "link.txt")
if (-not (Test-Path $listPath)) { Write-Host "WARN: link.txt not found"; exit 0 }
$links = Get-Content $listPath | Where-Object { $_.Trim().Length -gt 0 }

# Extract thread id
function Get-ThreadId([string]$href) {
  $m = [regex]::Match($href,'\.(\d+)/?$')
  if ($m.Success) { return [int]$m.Groups[1].Value } else { return 0 }
}

foreach ($link in $links) {
  Write-Host "DEBUG: Processing link=[$link]"

  if ($link -like "https://forum.rg-adguard.net/forums/*") {
    $html = Invoke-WebRequest $link -Headers @{ Cookie = $cookieHeader } -UserAgent $ua
    $threads = $html.Links | Where-Object { $_.href -like "/threads/*" }
    Write-Host "DEBUG: Found $($threads.Count) threads in section"

    # Only en-ru threads; pick newest by id
    $enruThreads = $threads | Where-Object { $_.href -match '(?i)en-ru' -or $_.innerText -match '(?i)en-ru' }
    $selected = $enruThreads | Sort-Object @{Expression={Get-ThreadId $_.href};Descending=$true} | Select-Object -First 1
    if (-not $selected) { Write-Host "WARN: No en-ru thread found"; continue }

    $threadUrl = "https://forum.rg-adguard.net$($selected.href)"
    Write-Host "DEBUG: threadUrl=[$threadUrl]"

    $page = Invoke-WebRequest $threadUrl -Headers @{ Cookie = $cookieHeader } -UserAgent $ua
    if ($page.Content -notmatch "tuthanika") { Write-Host "WARN: Login failed"; continue }

    $goMatches = [regex]::Matches($page.Content,'https://go\.rg-adguard\.net/[^\s"<>]+')
    Write-Host "DEBUG: goLinks found=[$($goMatches.Count)]"
    if ($goMatches.Count -lt 1) { Write-Host "WARN: No goLink found"; continue }

    $shareLink = Resolve-FinalUrl -StartUrl $goMatches[0].Value
    Write-Host "DEBUG: shareLink=[$shareLink]"
    if ([string]::IsNullOrWhiteSpace($shareLink)) { Write-Host "WARN: shareLink empty"; continue }

    Process-DownloaderOutput -SourceUrl $shareLink -PipePath $pipePath
  }
  elseif ($link -like "https://forum.rg-adguard.net/threads/*") {
    $page = Invoke-WebRequest $link -Headers @{ Cookie = $cookieHeader } -UserAgent $ua
    if ($page.Content -notmatch "tuthanika") { Write-Host "WARN: Login failed"; continue }

    $goMatches = [regex]::Matches($page.Content,'https://go\.rg-adguard\.net/[^\s"<>]+')
    Write-Host "DEBUG: goLinks found=[$($goMatches.Count)]"
    if ($goMatches.Count -lt 1) { Write-Host "WARN: No goLink found"; continue }

    $shareLink = Resolve-FinalUrl -StartUrl $goMatches[0].Value
    Write-Host "DEBUG: shareLink=[$shareLink]"
    if ([string]::IsNullOrWhiteSpace($shareLink)) { Write-Host "WARN: shareLink empty"; continue }

    Process-DownloaderOutput -SourceUrl $shareLink -PipePath $pipePath
  }
  elseif ($link -like "https://cloud.mail.ru/*") {
    Process-DownloaderOutput -SourceUrl $link -PipePath $pipePath
  }
  else {
    Write-Host "WARN: Unknown link type"
  }
}
