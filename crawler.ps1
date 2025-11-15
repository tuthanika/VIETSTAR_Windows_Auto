$pipePath = (Join-Path $env:SCRIPT_PATH "links.final.txt")
Remove-Item $pipePath -ErrorAction Ignore
Write-Host "DEBUG: Removed old links.final.txt"

$shareLinks = Get-Content (Join-Path $env:REPO_PATH "link.txt") | Where-Object { $_.Trim().Length -gt 0 }
Write-Host "DEBUG: link.txt count=$($shareLinks.Count)"

foreach ($link in $shareLinks) {
    Write-Host "DEBUG: Processing link=[$link]"

    $realLink = ""
    $filenameA = ""

    if ($link -like "https://forum.rg-adguard.net/*") {
        Write-Host "DEBUG: Forum link detected"
        $html   = Invoke-WebRequest $link -UseBasicParsing -Headers @{ Cookie = $env:FORUM_COOKIE }
        $thread = $html.Links | Where-Object { $_.innerText -match "

\[En/Ru\]

" } | Select-Object -First 1
        if (-not $thread) { Write-Host "WARN: No thread found"; continue }

        $slugRaw   = ($thread.href -split "/")[2]
        $filenameA = $slugRaw -replace "\.\d+$",""
        Write-Host "DEBUG: filenameA from forum=[$filenameA]"

        $threadUrl = "https://forum.rg-adguard.net$($thread.href)"
        $page      = Invoke-WebRequest $threadUrl -UseBasicParsing -Headers @{ Cookie = $env:FORUM_COOKIE }
        $goLink    = ($page.Links | Where-Object { $_.href -like "https://go.rg-adguard.net/*" } | Select-Object -First 1).href
        if (-not $goLink) { Write-Host "WARN: No goLink"; continue }

        $resp      = Invoke-WebRequest $goLink -MaximumRedirection 0 -ErrorAction SilentlyContinue
        $shareLink = $resp.Headers["Location"]
        Write-Host "DEBUG: shareLink=[$shareLink]"
        if ([string]::IsNullOrWhiteSpace($shareLink)) { continue }

        $realLink  = (& php (Join-Path $env:REPO_PATH "downloader.php") $shareLink | Out-String).Trim()
        Write-Host "DEBUG: downloader output=[$realLink]"
    }
    elseif ($link -like "https://cloud.mail.ru/*") {
        Write-Host "DEBUG: Cloud link detected"
        $realLink  = (& php (Join-Path $env:REPO_PATH "downloader.php") $link | Out-String).Trim()
        Write-Host "DEBUG: downloader output=[$realLink]"
        $filenameA = [System.IO.Path]::GetFileName($realLink)
        if (-not ($filenameA -match '\.iso$')) { $filenameA = "$filenameA.iso" }
        Write-Host "DEBUG: filenameA from cloud=[$filenameA]"
    }
    else {
        Write-Host "WARN: Unknown link type, skip [$link]"
        continue
    }

    if (-not $realLink -or -not ($realLink -match '^https?://')) {
        Write-Host "WARN: realLink invalid [$realLink]"
        continue
    }

    $RawJson = (& (Join-Path $env:REPO_PATH "check-exists.ps1") -FileNameA $filenameA -Folder "Auto" | Out-String).Trim()
    Write-Host "DEBUG: check-exists raw=[$RawJson]"

    if ($RawJson.StartsWith("{")) {
        $Info = $RawJson | ConvertFrom-Json
        Write-Host "DEBUG: Parsed JSON status=[$($Info.status)]"
        $pipeLine = "$($Info.status)|$realLink|Auto|$filenameA|$($Info.baseKey)|$($Info.dateTag)|$($Info.deleteList)"
        Write-Host "DEBUG: Write pipe=[$pipeLine]"
        Add-Content $pipePath $pipeLine
    }
}
