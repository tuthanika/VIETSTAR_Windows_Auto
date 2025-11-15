$raw   = [Environment]::GetEnvironmentVariable("FILE_CODE_RULES")
$rules = $raw | ConvertFrom-Json

foreach ($rule in $rules) {
  $folder = $rule.Folder

  if ($rule.Link) {
    # Crawl forum
    $html   = Invoke-WebRequest $rule.Link -UseBasicParsing
    $thread = $html.Links | Where-Object { $_.innerText -match "\[En/Ru\]" } | Select-Object -First 1
    if (-not $thread) { continue }

    $slugRaw   = ($thread.href -split "/")[2]
    $filenameA = $slugRaw -replace "\.\d+$",""

    # check-exists.ps1 nằm trong REPO_PATH
    $json = & (Join-Path $env:REPO_PATH "check-exists.ps1") -FileNameA $filenameA -Folder $folder
    $info = $json | ConvertFrom-Json
    if ($info.status -eq "exists") {
      Add-Content (Join-Path $env:SCRIPT_PATH "links.final.txt") "exists||$folder|$filenameA|||"
      continue
    }

    # Lấy link share từ thread
    $threadUrl = "https://forum.rg-adguard.net$($thread.href)"
    $page      = Invoke-WebRequest $threadUrl -UseBasicParsing -Headers @{ Cookie = $env:FORUM_COOKIE }
    $goLink    = ($page.Links | Where-Object { $_.href -like "https://go.rg-adguard.net/*" } | Select-Object -First 1).href
    if (-not $goLink) { continue }

    $resp      = Invoke-WebRequest $goLink -MaximumRedirection 0 -ErrorAction SilentlyContinue
    $shareLink = $resp.Headers["Location"]

    # Resolve bằng downloader.php trong REPO_PATH
    $realLink  = & php (Join-Path $env:REPO_PATH "downloader.php") --url "$shareLink"

    Add-Content (Join-Path $env:SCRIPT_PATH "links.final.txt") "upload|$realLink|$folder|$filenameA|||"
  }
  else {
    # Không có forum Link → dùng link.txt trong REPO_PATH
    $shareLinks = Get-Content (Join-Path $env:REPO_PATH "link.txt")
    foreach ($shareLink in $shareLinks) {
      $filenameA = [System.IO.Path]::GetFileName($shareLink)
      $json = & (Join-Path $env:REPO_PATH "check-exists.ps1") -FileNameA $filenameA -Folder $folder
      $info = $json | ConvertFrom-Json
      if ($info.status -eq "exists") {
        Add-Content (Join-Path $env:SCRIPT_PATH "links.final.txt") "exists||$folder|$filenameA|||"
        continue
      }
      $realLink = & php (Join-Path $env:REPO_PATH "downloader.php") --url "$shareLink"
      Add-Content (Join-Path $env:SCRIPT_PATH "links.final.txt") "upload|$realLink|$folder|$filenameA|||"
    }
  }
}
