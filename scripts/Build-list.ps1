# ENV
$pipePath = (Join-Path $env:SCRIPT_PATH "links.final.txt")
Remove-Item $pipePath -ErrorAction Ignore

# Error log (add)
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
    # Section → lấy threads theo rules
    try {
      $results = & (Join-Path $env:REPO_PATH "scripts\threads.ps1") -SectionUrl $link -ThreadFilter $threadFilter
      if (-not $?) { Add-Content -Path $errPath -Value "ERROR threads.ps1 returned failure for SectionUrl=$link"; continue }
    } catch {
      Add-Content -Path $errPath -Value "ERROR threads.ps1 exception: $($_.Exception.Message)"
      continue
    }

    foreach ($res in $results) {
      $partsRes = $res.Split('|')
      $folder   = $partsRes[0]
      $threadUrl= $partsRes[1]

      try {
        $goLink = & (Join-Path $env:REPO_PATH "scripts\go-link.ps1") -ThreadUrl $threadUrl
        if (-not $?) { Add-Content -Path $errPath -Value "ERROR go-link.ps1 returned failure for ThreadUrl=$threadUrl" }
      } catch {
        Add-Content -Path $errPath -Value "ERROR go-link.ps1 exception: $($_.Exception.Message) (ThreadUrl=$threadUrl)"
        $goLink = $null
      }
      if (-not $goLink) { continue }

      try {
        $shareLink = & (Join-Path $env:REPO_PATH "scripts\redirect.ps1") -StartUrl $goLink
        if (-not $?) { Add-Content -Path $errPath -Value "ERROR redirect.ps1 returned failure for StartUrl=$goLink" }
      } catch {
        Add-Content -Path $errPath -Value "ERROR redirect.ps1 exception: $($_.Exception.Message) (StartUrl=$goLink)"
        $shareLink = $null
      }
      if (-not $shareLink) { continue }

      if (-not [string]::IsNullOrWhiteSpace($downloadKey)) {
        $shareLink = ($shareLink.TrimEnd('/')) + "/" + $downloadKey
      }

      try {
        & (Join-Path $env:REPO_PATH "scripts\downloader.ps1") -SourceUrl $shareLink -PipePath $pipePath
        if (-not $?) { Add-Content -Path $errPath -Value "ERROR downloader.ps1 returned failure for SourceUrl=$shareLink" }
        if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
          Add-Content -Path $errPath -Value "ERROR downloader.ps1 exit code=$LASTEXITCODE for SourceUrl=$shareLink"
        }
      } catch {
        Add-Content -Path $errPath -Value "ERROR downloader.ps1 exception: $($_.Exception.Message) (SourceUrl=$shareLink)"
      }
    }
  }
  elseif ($link -like "https://forum.rg-adguard.net/threads/*") {
    try {
      $goLink = & (Join-Path $env:REPO_PATH "scripts\go-link.ps1") -ThreadUrl $link
      if (-not $?) { Add-Content -Path $errPath -Value "ERROR go-link.ps1 returned failure for ThreadUrl=$link" }
    } catch {
      Add-Content -Path $errPath -Value "ERROR go-link.ps1 exception: $($_.Exception.Message) (ThreadUrl=$link)"
      $goLink = $null
    }
    if (-not $goLink) { continue }

    try {
      $shareLink = & (Join-Path $env:REPO_PATH "scripts\redirect.ps1") -StartUrl $goLink
      if (-not $?) { Add-Content -Path $errPath -Value "ERROR redirect.ps1 returned failure for StartUrl=$goLink" }
    } catch {
      Add-Content -Path $errPath -Value "ERROR redirect.ps1 exception: $($_.Exception.Message) (StartUrl=$goLink)"
      $shareLink = $null
    }
    if (-not $shareLink) { continue }

    if (-not [string]::IsNullOrWhiteSpace($downloadKey)) {
      $shareLink = ($shareLink.TrimEnd('/')) + "/" + $downloadKey
    }

    try {
      & (Join-Path $env:REPO_PATH "scripts\downloader.ps1") -SourceUrl $shareLink -PipePath $pipePath
      if (-not $?) { Add-Content -Path $errPath -Value "ERROR downloader.ps1 returned failure for SourceUrl=$shareLink" }
      if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
        Add-Content -Path $errPath -Value "ERROR downloader.ps1 exit code=$LASTEXITCODE for SourceUrl=$shareLink"
      }
    } catch {
      Add-Content -Path $errPath -Value "ERROR downloader.ps1 exception: $($_.Exception.Message) (SourceUrl=$shareLink)"
    }
  }
  elseif ($link -like "https://cloud.mail.ru/*") {
    try {
      & (Join-Path $env:REPO_PATH "scripts\downloader.ps1") -SourceUrl $link -PipePath $pipePath
      if (-not $?) { Add-Content -Path $errPath -Value "ERROR downloader.ps1 returned failure for SourceUrl=$link" }
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
