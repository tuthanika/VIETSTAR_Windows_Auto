# crawler.ps1

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Process-Link {
  param(
    [string]$ShareLink,
    [string]$Folder
  )

  # 1) Resolve share → real direct link
  $RealLink = (& php (Join-Path $env:REPO_PATH "downloader.php") $ShareLink | Out-String).Trim()
  Write-Host "DEBUG downloader output: [$RealLink]"
  if ([string]::IsNullOrWhiteSpace($RealLink)) { return }

  # 2) Derive filenameA từ real link (ưu tiên), fallback từ share link
  $fnFromReal  = [System.IO.Path]::GetFileName($RealLink)
  $fnFromShare = [System.IO.Path]::GetFileName($ShareLink)

  $FileNameA = if (![string]::IsNullOrWhiteSpace($fnFromReal)) { $fnFromReal }
               elseif (![string]::IsNullOrWhiteSpace($fnFromShare)) { $fnFromShare }
               else { "unknown.iso" }

  if (-not ($FileNameA -match '\.iso$')) { $FileNameA = "$FileNameA.iso" }

  # 3) Check-exists (JSON)
  $RawJson = (& (Join-Path $env:REPO_PATH "check-exists.ps1") -FileNameA $FileNameA -Folder $Folder | Out-String).Trim()
  if (-not $RawJson.StartsWith("{")) { return }
  $Info = $RawJson | ConvertFrom-Json

  # 4) Ghi pipe đầy đủ
  $pipePath = (Join-Path $env:SCRIPT_PATH "links.final.txt")
  Add-Content $pipePath "$($Info.status)|$RealLink|$Folder|$FileNameA|$($Info.baseKey)|$($Info.dateTag)|$($Info.deleteList)"
}

# --- Main ---
$rulesRaw = [Environment]::GetEnvironmentVariable("FILE_CODE_RULES")
if ([string]::IsNullOrWhiteSpace($rulesRaw)) { exit 0 }
$rules = $rulesRaw | ConvertFrom-Json

Remove-Item (Join-Path $env:SCRIPT_PATH "links.final.txt") -ErrorAction Ignore

foreach ($rule in $rules) {
  $folder = $rule.Folder

  if ($rule.PSObject.Properties.Name -contains 'Link' -and -not [string]::IsNullOrWhiteSpace($rule.Link)) {
    # Forum flow
    $html   = Invoke-WebRequest $rule.Link -UseBasicParsing
    $thread = $html.Links | Where-Object { $_.innerText -match "\[En/Ru\]" } | Select-Object -First 1
    if (-not $thread) { continue }

    $threadUrl = "https://forum.rg-adguard.net$($thread.href)"
    $page      = Invoke-WebRequest $threadUrl -UseBasicParsing -Headers @{ Cookie = $env:FORUM_COOKIE }
    $goLink    = ($page.Links | Where-Object { $_.href -like "https://go.rg-adguard.net/*" } | Select-Object -First 1).href
    if (-not $goLink) { continue }

    $resp      = Invoke-WebRequest $goLink -MaximumRedirection 0 -ErrorAction SilentlyContinue
    $shareLink = $resp.Headers["Location"]
    if ([string]::IsNullOrWhiteSpace($shareLink)) { continue }

    Process-Link -ShareLink $shareLink -Folder $folder
  }
  else {
    # link.txt flow (mỗi dòng một share link)
    $listPath = (Join-Path $env:REPO_PATH "link.txt")
    if (-not (Test-Path $listPath)) { continue }
    $shareLinks = Get-Content $listPath | Where-Object { $_.Trim().Length -gt 0 }

    foreach ($shareLink in $shareLinks) {
      Process-Link -ShareLink $shareLink -Folder $folder
    }
  }
}
