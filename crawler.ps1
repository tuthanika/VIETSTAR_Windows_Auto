# Vars
$ua = [Environment]::GetEnvironmentVariable("FORUM_UA")
if ([string]::IsNullOrWhiteSpace($ua)) {
  $ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36"
}
$cookieHeader = [Environment]::GetEnvironmentVariable("FORUM_COOKIE")

# Read rules
$rulesRaw = [Environment]::GetEnvironmentVariable("FILE_CODE_RULES")
if ([string]::IsNullOrWhiteSpace($rulesRaw)) { $rules = @() } else { try { $rules = $rulesRaw | ConvertFrom-Json } catch { $rules = @() } }

function Resolve-Folder {
  param([string]$FileNameA)
  $folder = "Auto"
  foreach ($rule in $rules) {
    if ($FileNameA.ToLower() -like $rule.Pattern.ToLower()) { $folder = $rule.Folder; break }
  }
  Write-Host "DEBUG: matched folder=[$folder] for filenameA=[$FileNameA]"
  return $folder
}

$pipePath = (Join-Path $env:SCRIPT_PATH "links.final.txt")
Remove-Item $pipePath -ErrorAction Ignore

$listPath = (Join-Path $env:REPO_PATH "link.txt")
$shareLinks = Get-Content $listPath | Where-Object { $_.Trim().Length -gt 0 }

foreach ($link in $shareLinks) {
  Write-Host "DEBUG: Processing link=[$link]"
  $realLink  = ""
  $filenameA = ""

  if ($link -like "https://forum.rg-adguard.net/threads/*") {
    $page = Invoke-WebRequest $link -Headers @{ Cookie = $cookieHeader } -UserAgent $ua
    if ($page.Content -match "tuthanika") { Write-Host "DEBUG: Login OK" } else { Write-Host "WARN: Login failed"; continue }
    $goMatches = [regex]::Matches($page.Content, 'https://go\.rg-adguard\.net/[^\s"<>]+')
    if ($goMatches.Count -lt 1) { Write-Host "WARN: No goLink"; continue }
    $goLink = $goMatches[0].Value
    $resp      = Invoke-WebRequest $goLink -MaximumRedirection 0 -ErrorAction SilentlyContinue -UserAgent $ua
    $shareLink = $resp.Headers["Location"]
    $realLink  = (& php (Join-Path $env:REPO_PATH "downloader.php") $shareLink | Out-String).Trim()
    $slugRaw   = ($link.TrimEnd('/') -split '/')[2]
    $filenameA = ($slugRaw -replace "\.\d+$","") + ".iso"
  }
  elseif ($link -like "https://cloud.mail.ru/*") {
    $realLink  = (& php (Join-Path $env:REPO_PATH "downloader.php") $link | Out-String).Trim()
    $filenameA = [System.IO.Path]::GetFileName($realLink)
    if (-not ($filenameA -match '\.iso$')) { $filenameA = "$filenameA.iso" }
  }
  else { continue }

  if (-not $realLink) { continue }
  $folder = Resolve-Folder -FileNameA $filenameA

  $RawJson = (& (Join-Path $env:REPO_PATH "check-exists.ps1") -FileNameA $filenameA -Folder $folder | Out-String).Trim()
  if ($RawJson.StartsWith("{")) {
    $Info = $RawJson | ConvertFrom-Json
    $pipeLine = "$($Info.status)|$realLink|$folder|$filenameA|$($Info.baseKey)|$($Info.dateTag)|$($Info.deleteList)"
    Add-Content $pipePath $pipeLine
  }
}
