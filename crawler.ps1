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

# Resolve folder strictly via rules
function Resolve-Folder {
    param([string]$FileNameA)

    foreach ($r in $rules) {
        if ($null -eq $r.Patterns) { continue }
        foreach ($pat in $r.Patterns) {
            if ([string]::IsNullOrWhiteSpace($pat)) { continue }
            $p = $pat.ToLower()
            if ($FileNameA.ToLower() -like $p) {
                Write-Host "DEBUG: check-exists matched folder=[$($r.Folder)] for filenameA=[$FileNameA] via pattern=[$pat]"
                return $r.Folder
            }
        }
    }
    Write-Host "WARN: no folder rule matched for filenameA=[$FileNameA]"
    return $null
}

# Redirect chain debug
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
$rawLinks = Get-Content $listPath | Where-Object { $_.Trim().Length -gt 0 }

# Extract thread id
function Get-ThreadId([string]$href) {
  $m = [regex]::Match($href,'\.(\d+)/?$')
  if ($m.Success) { return [int]$m.Groups[1].Value } else { return 0 }
}

foreach ($raw in $rawLinks) {
  $parts = $raw.Split('|')
  $link          = $parts[0].Trim()
  $threadFilter  = if ($parts.Count -gt 1) { $parts[1].Trim() } else { "" }
  $downloadKey   = if ($parts.Count -gt 2) { $parts[2].Trim() } else { "" }

  Write-Host "DEBUG: Processing link=[$link] (threadFilter=[$threadFilter], downloadKey=[$downloadKey])"

  if ($link -like "https://forum.rg-adguard.net/forums/*") {
    $html = Invoke-WebRequest $link -Headers @{ Cookie = $cookieHeader } -UserAgent $ua
    $threads = $html.Links | Where-Object { $_.href -like "/threads/*" }
    Write-Host "DEBUG: Found $($threads.Count) threads in section"

  if (-not [string]::IsNullOrWhiteSpace($threadFilter)) {
      # Chuyển cú pháp kiểu CMD (*...) thành regex
      $regexPattern = "(?i)" + ($threadFilter -replace '\*','.*')
      $filteredThreads = $threads | Where-Object {
          $_.href -match $regexPattern -or $_.innerText -match $regexPattern
      }
  } else {
      $filteredThreads = $threads | Where-Object {
          $_.href -match '(?i)en-ru' -or $_.innerText -match '(?i)en-ru'
      }
  }
  Write-Host "DEBUG: filteredThreads count=$($filteredThreads.Count)"

    $chosen = @{}
    $results = @()
    foreach ($r in $rules) {
      $folder   = $r.Folder
      $matches  = @()

      foreach ($pat in $r.Patterns) {
        $tmp = $filteredThreads | Where-Object { $_.href -like $pat -or $_.innerText -like $pat }
        if ($tmp.Count -gt 0) { $matches += $tmp }
      }

      Write-Host "DEBUG: Rule [$folder] matched $($matches.Count) threads"
      if ($matches.Count -eq 0) { continue }

      $selected = $matches | Sort-Object @{Expression={Get-ThreadId $_.href};Descending=$true} | Select-Object -First 1
      Write-Host "DEBUG: Rule [$folder] selected thread href=[$($selected.href)]"

      if (-not $chosen.ContainsKey($selected.href)) {
        $chosen[$selected.href] = $true
        $results += @{ Folder=$folder; Href=$selected.href }
      } else {
        Write-Host "DEBUG: Rule [$folder] skipped because thread [$($selected.href)] already taken"
      }
    }

    foreach ($res in $results) {
      $threadUrl = "https://forum.rg-adguard.net$($res.Href)"
      Write-Host "DEBUG: threadUrl=[$threadUrl] for folder=[$($res.Folder)]"
      $page = Invoke-WebRequest $threadUrl -Headers @{ Cookie = $cookieHeader } -UserAgent $ua
      if ($page.Content -notmatch "tuthanika") { Write-Host "WARN: Login failed"; continue }
      $goMatches = [regex]::Matches($page.Content,'https://go\.rg-adguard\.net/[^\s"<>]+')
      Write-Host "DEBUG: goLinks found=$($goMatches.Count)"
      if ($goMatches.Count -lt 1) { Write-Host "WARN: No goLink found"; continue }
      $shareLink = Resolve-FinalUrl -StartUrl $goMatches[0].Value
      Write-Host "DEBUG: shareLink=[$shareLink]"
      if ([string]::IsNullOrWhiteSpace($shareLink)) { Write-Host "WARN: shareLink empty"; continue }

      # Nếu có downloadKey từ link.txt → nối vào cuối shareLink
      if (-not [string]::IsNullOrWhiteSpace($downloadKey)) {
        $shareLink = ($shareLink.TrimEnd('/')) + "/" + $downloadKey
        Write-Host "DEBUG: shareLink with downloadKey=[$shareLink]"
      }

      Process-DownloaderOutput -SourceUrl $shareLink -PipePath $pipePath
    }
  }
  elseif ($link -like "https://forum.rg-adguard.net/threads/*") {
    $page = Invoke-WebRequest $link -Headers @{ Cookie = $cookieHeader } -UserAgent $ua
    if ($page.Content -notmatch "tuthanika") { Write-Host "WARN: Login failed"; continue }
    $goMatches = [regex]::Matches($page.Content,'https://go\.rg-adguard\.net/[^\s"<>]+')
    Write-Host "DEBUG: goLinks found=$($goMatches.Count)"
    if ($goMatches.Count -lt 1) { Write-Host "WARN: No goLink found"; continue }
    $shareLink = Resolve-FinalUrl -StartUrl $goMatches[0].Value
    Write-Host "DEBUG: shareLink=[$shareLink]"
    if ([string]::IsNullOrWhiteSpace($shareLink)) { Write-Host "WARN: shareLink empty"; continue }

    if (-not [string]::IsNullOrWhiteSpace($downloadKey)) {
      $shareLink = ($shareLink.TrimEnd('/')) + "/" + $downloadKey
      Write-Host "DEBUG: shareLink with downloadKey=[$shareLink]"
    }

    Process-DownloaderOutput -SourceUrl $shareLink -PipePath $pipePath
  }
  elseif ($link -like "https://cloud.mail.ru/*") {
    # Cloud link trực tiếp: truyền nguyên xi, có thể viết thẳng /*.iso trong link.txt
    Process-DownloaderOutput -SourceUrl $link -PipePath $pipePath
  }
  else {
    Write-Host "WARN: Unknown link type"
  }
}

# Sau khi xử lý xong toàn bộ links, có thể in thống kê
if (Test-Path $pipePath) {
  $count = (Get-Content $pipePath | Measure-Object).Count
  Write-Host "DEBUG: links.final.txt count=$count"
  if ($count -eq 0) {
    Write-Host "No new links. Done."
  } else {
    Write-Host "Processing finished, $count links written."
  }
}
