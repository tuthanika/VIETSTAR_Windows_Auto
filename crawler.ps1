$pipePath = (Join-Path $env:SCRIPT_PATH "links.final.txt")
Remove-Item $pipePath -ErrorAction Ignore

$shareLinks = Get-Content (Join-Path $env:REPO_PATH "link.txt") | Where-Object { $_.Trim().Length -gt 0 }

foreach ($link in $shareLinks) {
    if ($link -like "https://forum.rg-adguard.net/*") {
        # Forum flow
        $html   = Invoke-WebRequest $link -UseBasicParsing -Headers @{ Cookie = $env:FORUM_COOKIE }
        $thread = $html.Links | Where-Object { $_.innerText -match "\[En/Ru\]" } | Select-Object -First 1
        if (-not $thread) { continue }

        $slugRaw   = ($thread.href -split "/")[2]
        $filenameA = $slugRaw -replace "\.\d+$",""

        $threadUrl = "https://forum.rg-adguard.net$($thread.href)"
        $page      = Invoke-WebRequest $threadUrl -UseBasicParsing -Headers @{ Cookie = $env:FORUM_COOKIE }
        $goLink    = ($page.Links | Where-Object { $_.href -like "https://go.rg-adguard.net/*" } | Select-Object -First 1).href
        if (-not $goLink) { continue }

        $resp      = Invoke-WebRequest $goLink -MaximumRedirection 0 -ErrorAction SilentlyContinue
        $shareLink = $resp.Headers["Location"]
        if ([string]::IsNullOrWhiteSpace($shareLink)) { continue }

        $realLink  = (& php (Join-Path $env:REPO_PATH "downloader.php") $shareLink | Out-String).Trim()
    }
    elseif ($link -like "https://cloud.mail.ru/*") {
        # Cloud share flow
        $realLink  = (& php (Join-Path $env:REPO_PATH "downloader.php") $link | Out-String).Trim()
        $filenameA = [System.IO.Path]::GetFileName($realLink)
        if (-not ($filenameA -match '\.iso$')) { $filenameA = "$filenameA.iso" }
    }
    else {
        Write-Host "Bỏ qua link không nhận diện được: $link"
        continue
    }

    # Check-exists và ghi pipe
    $RawJson = (& (Join-Path $env:REPO_PATH "check-exists.ps1") -FileNameA $filenameA -Folder "Auto" | Out-String).Trim()
    if ($RawJson.StartsWith("{")) {
        $Info = $RawJson | ConvertFrom-Json
        Add-Content $pipePath "$($Info.status)|$realLink|Auto|$filenameA|$($Info.baseKey)|$($Info.dateTag)|$($Info.deleteList)"
    }
}
