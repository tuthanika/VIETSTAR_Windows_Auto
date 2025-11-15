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

# Optional: validate rule consistency (log-only, no modification)
function Validate-Rules {
  param([array]$rules)
  $i = 0
  foreach ($r in $rules) {
    $i++
    $p = "$($r.Pattern)"
    $f = "$($r.Folder)"
    if ([string]::IsNullOrWhiteSpace($p) -or [string]::IsNullOrWhiteSpace($f)) {
      Write-Host "WARN: Rule#$i missing Pattern or Folder"
      continue
    }
    # Heuristic: warn if obvious mismatch (e.g., pattern contains "xp" but folder doesn't)
    if ($p -match 'xp' -and ($f -notmatch 'xp')) { Write-Host "WARN: Rule#$i pattern=[xp] but folder=[$f]" }
    if ($p -match 'vista' -and ($f -notmatch 'vista')) { Write-Host "WARN: Rule#$i pattern=[vista] but folder=[$f]" }
    if ($p -match '8\.1' -and ($f -notmatch '8')) { Write-Host "WARN: Rule#$i pattern=[8.1] but folder=[$f]" }
    if ($p -match 'windows\s*7|windows[_-]7|windows7' -and ($f -notmatch '7')) { Write-Host "WARN: Rule#$i pattern=[7] but folder=[$f]" }
    if ($p -match 'windows\s*8|windows[_-]8|windows8' -and ($f -notmatch '8')) { Write-Host "WARN: Rule#$i pattern=[8] but folder=[$f]" }
    if ($p -match 'windows\s*10|windows[_-]10|windows10' -and ($f -notmatch '10')) { Write-Host "WARN: Rule#$i pattern=[10] but folder=[$f]" }
    if ($p -match 'windows\s*11|windows[_-]11|windows11' -and ($f -notmatch '11')) { Write-Host "WARN: Rule#$i pattern=[11] but folder=[$f]" }
    Write-Host "DEBUG: Rule#$i Pattern=[$p] → Folder=[$f]"
  }
}
Validate-Rules -rules $rules

# Resolve folder strictly via rules in the given order (first match wins)
function Resolve-Folder {
  param([string]$FileNameA)

  $index = 0
  foreach ($r in $rules) {
    $index++
    if ([string]::IsNullOrWhiteSpace($r.Pattern)) { continue }
    if ($FileNameA -like $r.Pattern) {
      Write-Host "DEBUG: matched Rule#$index → folder=[$($r.Folder)] for filenameA=[$FileNameA] via pattern=[$($r.Pattern)]"
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
    Write-Host "DEBUG: hop#$i request=[$current]"
    $resp = $client.GetAsync($current).Result
    $status = [int]$resp.StatusCode
    Write-Host "DEBUG: hop#$i status=[$status]"
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

# Process downloader.php output
function Process-DownloaderOutput {
  param([string]$SourceUrl,[string]$PipePath)

  $dlOutput  = (& php (Join-Path $env:REPO_PATH "downloader.php") $SourceUrl | Out-String)
  $realLines = ($dlOutput -replace "`r`n","`n" -replace "`r","`n").Trim() -split "`n"
  Write-Host "DEBUG: downloader lines count=[$($realLines.Count)]"

  foreach ($rl in $realLines) {
    # reset per-iteration state
    $rl = $rl.Trim()
    if ([string]::IsNullOrWhiteSpace($rl)) { continue }
    if (-not ($rl -match '^https?://')) { Write-Host "WARN: skip non-http line"; continue }

    Write-Host "DEBUG: downloader line=[$rl]"
    $filenameA = [System.IO.Path]::GetFileName($rl)
    if ([string]::IsNullOrWhiteSpace($filenameA)) { Write-Host "WARN: empty filenameA"; continue }

    $folder = Resolve-Folder -FileNameA $filenameA
    if (-not $folder) { Write-Host "WARN: skip file due to no matching rule"; continue }

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

    # en-ru only; pick newest by id
    $enruThreads = $threads | Where-Object { $_.href -match '(?i)en-ru' -or $_.innerText -match '(?i)en-ru' }
    $selected = $enruThreads | Sort-Object @{Expression={Get-ThreadId $_.href};Descending=$true} | Select-Object -First 1
    if (-not $selected) { Write-Host "WARN: No en-ru thread found"; continue }

    $threadUrl = "https://forum.rg-adguard.net$($selected.href)"
    Write-Host "DEBUG: threadUrl=[$threadUrl]"

    $page = Invoke-WebRequest $threadUrl -Headers @{ Cookie = $cookieHeader } -UserAgent $ua
    if ($page.Content -notmatch "tuthanika") { Write-Host "WARN: Login failed"; continue }

    $goMatches = [regex]::Matches($page.Content,'https://go\.rg-adguard\.net/[^\s"<>]+')
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
