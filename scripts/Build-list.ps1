# ENV
$pipePath = (Join-Path $env:SCRIPT_PATH "links.final.txt")
Remove-Item $pipePath -ErrorAction Ignore

$listPath = (Join-Path $env:REPO_PATH "link.txt")
if (-not (Test-Path $listPath)) { Write-Host "WARN: link.txt not found"; exit 0 }
$rawLinks = Get-Content $listPath | Where-Object { $_.Trim().Length -gt 0 }

foreach ($raw in $rawLinks) {
  $parts = $raw.Split('|')
  $link          = $parts[0].Trim()
  $threadFilter  = if ($parts.Count -gt 1) { $parts[1].Trim() } else { "" }
  $downloadKey   = if ($parts.Count -gt 2) { $parts[2].Trim() } else { "" }

  Write-Host "DEBUG: Processing link=[$link] (threadFilter=[$threadFilter], downloadKey=[$downloadKey])"

  if ($link -like "https://forum.rg-adguard.net/forums/*") {
    # Section → lấy threads theo rules
    $results = & (Join-Path $env:REPO_PATH "scripts\threads.ps1") -SectionUrl $link -ThreadFilter $threadFilter
    foreach ($res in $results) {
      $partsRes = $res.Split('|')
      $folder   = $partsRes[0]
      $threadUrl= $partsRes[1]

      $goLink = & (Join-Path $env:REPO_PATH "scripts\go-link.ps1") -ThreadUrl $threadUrl
      if (-not $goLink) { continue }

      $shareLink = & (Join-Path $env:REPO_PATH "scripts\redirect.ps1") -StartUrl $goLink
      if (-not $shareLink) { continue }

      if (-not [string]::IsNullOrWhiteSpace($downloadKey)) {
        $shareLink = ($shareLink.TrimEnd('/')) + "/" + $downloadKey
      }

      & (Join-Path $env:REPO_PATH "scripts\downloader.ps1") -SourceUrl $shareLink -PipePath $pipePath
    }
  }
  elseif ($link -like "https://forum.rg-adguard.net/threads/*") {
    $goLink = & (Join-Path $env:REPO_PATH "scripts\go-link.ps1") -ThreadUrl $link
    if (-not $goLink) { continue }

    $shareLink = & (Join-Path $env:REPO_PATH "scripts\redirect.ps1") -StartUrl $goLink
    if (-not $shareLink) { continue }

    if (-not [string]::IsNullOrWhiteSpace($downloadKey)) {
      $shareLink = ($shareLink.TrimEnd('/')) + "/" + $downloadKey
    }

    & (Join-Path $env:REPO_PATH "scripts\downloader.ps1") -SourceUrl $shareLink -PipePath $pipePath
  }
  elseif ($link -like "https://cloud.mail.ru/*") {
    & (Join-Path $env:REPO_PATH "scripts\downloader.ps1") -SourceUrl $link -PipePath $pipePath
  }
  else {
    Write-Host "WARN: Unknown link type"
  }
}

if (Test-Path $pipePath) {
  Write-Host "=== links.final.txt content ==="
  Get-Content $pipePath | ForEach-Object { Write-Host $_ }
  Write-Host "=== end of file ==="
}


# Sau khi xử lý xong toàn bộ links, in thống kê
if (Test-Path $pipePath) {
  $count = (Get-Content $pipePath | Measure-Object).Count
  Write-Host "DEBUG: links.final.txt count=$count"
  if ($count -eq 0) {
    Write-Host "No new links. Done."
  } else {
    Write-Host "Processing finished, $count links written."
  }
}
