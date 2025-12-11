# ENV
$pipePath = (Join-Path $env:SCRIPT_PATH "links.final.txt")
Remove-Item $pipePath -ErrorAction Ignore

# Error log
$errPath = Join-Path $env:SCRIPT_PATH "errors.log"
Remove-Item $errPath -ErrorAction Ignore

# Debug log
$debugPath = Join-Path $env:SCRIPT_PATH "debug.log"
Remove-Item $debugPath -ErrorAction Ignore

$listPath = (Join-Path $env:REPO_PATH "link.txt")
if (-not (Test-Path $listPath)) { Write-Host "WARN: link.txt not found"; exit 0 }
$rawLinks = Get-Content $listPath | Where-Object { $_.Trim().Length -gt 0 }

function Run-Script {
    param([string]$scriptPath,[string]$args,[string]$label)

    Write-Host "=== Running $label ==="
    $out = & $scriptPath $args 2>&1
    $exit = $LASTEXITCODE

    # In ra màn hình
    $out | ForEach-Object { Write-Host "[$label] $_" }

    # Ghi vào debug.log
    Add-Content -Path $debugPath -Value "=== $label exit=$exit ==="
    $out | ForEach-Object { Add-Content -Path $debugPath -Value $_ }

    return @{ Output=$out; ExitCode=$exit }
}

function Run-Downloader {
    param([string]$url)

    $res = Run-Script (Join-Path $env:REPO_PATH "scripts\downloader.ps1") "-SourceUrl $url -PipePath $pipePath" "downloader.ps1 $url"

    if ($res.ExitCode -ne 0) {
        Add-Content -Path $errPath -Value "ERROR downloader.ps1 exit code=$($res.ExitCode) for SourceUrl=$url"
        $res.Output | ForEach-Object { Add-Content -Path $errPath -Value "  >> $_" }
    }
}

foreach ($raw in $rawLinks) {
  $parts = $raw.Split('|')
  $link          = $parts[0].Trim()
  $threadFilter  = if ($parts.Count -gt 1) { $parts[1].Trim() } else { "" }
  $downloadKey   = if ($parts.Count -gt 2) { $parts[2].Trim() } else { "" }

  Write-Host "DEBUG: Processing link=[$link] (threadFilter=[$threadFilter], downloadKey=[$downloadKey])"

  if ($link -like "https://forum.rg-adguard.net/forums/*") {
    $results = Run-Script (Join-Path $env:REPO_PATH "scripts\threads.ps1") "-SectionUrl $link -ThreadFilter $threadFilter" "threads.ps1"
    foreach ($res in $results.Output) {
      $partsRes = $res.Split('|')
      if ($partsRes.Count -lt 2) { continue }
      $folder   = $partsRes[0]
      $threadUrl= $partsRes[1]

      $goLinkRes = Run-Script (Join-Path $env:REPO_PATH "scripts\go-link.ps1") "-ThreadUrl $threadUrl" "go-link.ps1"
      $goLink = ($goLinkRes.Output | Select-Object -First 1)
      if (-not $goLink) { continue }

      $shareLinkRes = Run-Script (Join-Path $env:REPO_PATH "scripts\redirect.ps1") "-StartUrl $goLink" "redirect.ps1"
      $shareLink = ($shareLinkRes.Output | Select-Object -First 1)
      if (-not $shareLink) { continue }

      if (-not [string]::IsNullOrWhiteSpace($downloadKey)) {
        $shareLink = ($shareLink.TrimEnd('/')) + "/" + $downloadKey
      }

      Run-Downloader $shareLink
    }
  }
  elseif ($link -like "https://forum.rg-adguard.net/threads/*") {
    $goLinkRes = Run-Script (Join-Path $env:REPO_PATH "scripts\go-link.ps1") "-ThreadUrl $link" "go-link.ps1"
    $goLink = ($goLinkRes.Output | Select-Object -First 1)
    if (-not $goLink) { continue }

    $shareLinkRes = Run-Script (Join-Path $env:REPO_PATH "scripts\redirect.ps1") "-StartUrl $goLink" "redirect.ps1"
    $shareLink = ($shareLinkRes.Output | Select-Object -First 1)
    if (-not $shareLink) { continue }

    if (-not [string]::IsNullOrWhiteSpace($downloadKey)) {
      $shareLink = ($shareLink.TrimEnd('/')) + "/" + $downloadKey
    }

    Run-Downloader $shareLink
  }
  elseif ($link -like "https://cloud.mail.ru/*") {
    Run-Downloader $link
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
