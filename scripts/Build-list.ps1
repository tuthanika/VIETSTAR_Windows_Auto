# ENV
$pipePath = (Join-Path $env:SCRIPT_PATH "links.final.txt")
Remove-Item $pipePath -ErrorAction Ignore

# Error log
$errPath = Join-Path $env:SCRIPT_PATH "errors.log"
Remove-Item $errPath -ErrorAction Ignore

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

      try {
        $out = & (Join-Path $env:REPO_PATH "scripts\downloader.ps1") -SourceUrl $shareLink -PipePath $pipePath 2>&1
        $out | ForEach-Object { Write-Host "downloader.ps1 >> $_" }
        if (-not $?) {
          Add-Content -Path $errPath -Value "ERROR downloader.ps1 failure for SourceUrl=$shareLink"
          $out | ForEach-Object { Add-Content -Path $errPath -Value "  >> $_" }
        }
        if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
          Add-Content -Path $errPath -Value "ERROR downloader.ps1 exit code=$LASTEXITCODE for SourceUrl=$shareLink"
        }
      } catch {
        Add-Content -Path $errPath -Value "ERROR downloader.ps1 exception: $($_.Exception.Message) (SourceUrl=$shareLink)"
      }
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

    try {
      $out = & (Join-Path $env:REPO_PATH "scripts\downloader.ps1") -SourceUrl $shareLink -PipePath $pipePath 2>&1
      $out | ForEach-Object { Write-Host "downloader.ps1 >> $_" }
      if (-not $?) {
        Add-Content -Path $errPath -Value "ERROR downloader.ps1 failure for SourceUrl=$shareLink"
        $out | ForEach-Object { Add-Content -Path $errPath -Value "  >> $_" }
      }
      if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
        Add-Content -Path $errPath -Value "ERROR downloader.ps1 exit code=$LASTEXITCODE for SourceUrl=$shareLink"
      }
    } catch {
      Add-Content -Path $errPath -Value "ERROR downloader.ps1 exception: $($_.Exception.Message) (SourceUrl=$shareLink)"
    }
  }
  elseif ($link -like "https://cloud.mail.ru/*") {
    try {
      $out = & (Join-Path $env:REPO_PATH "scripts\downloader.ps1") -SourceUrl $link -PipePath $pipePath 2>&1
      $out | ForEach-Object { Write-Host "downloader.ps1 >> $_" }
      if (-not $?) {
        Add-Content -Path $errPath -Value "ERROR downloader.ps1 failure for SourceUrl=$link"
        $out | ForEach-Object { Add-Content -Path $errPath -Value "  >> $_" }
      }
      if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
        Add-Content -Path $errPath -Value "ERROR downloader.ps1 exit code=$LASTEXITCODE for SourceUrl=$link"
      }
    } catch {
      Add-Content -Path $errPath -Value "ERROR downloader.ps1 exception: $($_.Exception.Message) (SourceUrl=$link)"
    }
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

# Kiểm tra lỗi và thoát với exit code phù hợp
if (Test-Path $errPath) {
  Write-Host "=== Error summary ==="
  Get-Content $errPath | ForEach-Object { Write-Host $_ }
  Write-Host "=== End of errors ==="
  exit 1
} else {
  exit 0
}
