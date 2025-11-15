# Đọc rules từ env để phân loại folder
$rulesRaw = [Environment]::GetEnvironmentVariable("FILE_CODE_RULES")
if ([string]::IsNullOrWhiteSpace($rulesRaw)) {
  Write-Host "WARN: FILE_CODE_RULES env rỗng"; $rules = @()
} else {
  try { $rules = $rulesRaw | ConvertFrom-Json } catch { $rules = @() }
}
Write-Host "DEBUG: rules count=$($rules.Count)"

# Chuẩn bị pipe
$pipePath = (Join-Path $env:SCRIPT_PATH "links.final.txt")
Remove-Item $pipePath -ErrorAction Ignore
Write-Host "DEBUG: Removed old links.final.txt"

# Đọc link.txt
$listPath = (Join-Path $env:REPO_PATH "link.txt")
if (-not (Test-Path $listPath)) { Write-Host "WARN: link.txt không tồn tại"; exit 0 }
$shareLinks = Get-Content $listPath | Where-Object { $_.Trim().Length -gt 0 }
Write-Host "DEBUG: link.txt count=$($shareLinks.Count)"

# Helper: chọn folder theo filenameA dựa trên rules
function Resolve-Folder {
  param([string]$FileNameA)
  $folder = $null
  foreach ($rule in $rules) {
    if ($FileNameA -like $rule.Pattern) { $folder = $rule.Folder; break }
  }
  if (-not $folder) { $folder = "Auto" }
  Write-Host "DEBUG: matched folder=[$folder] for filenameA=[$FileNameA]"
  return $folder
}

foreach ($link in $shareLinks) {
    Write-Host "DEBUG: Processing link=[$link]"

    $realLink  = ""
    $filenameA = ""

    # Forum section
    if ($link -like "https://forum.rg-adguard.net/forums/*") {
        Write-Host "DEBUG: Forum section detected"
        $html = Invoke-WebRequest $link -UseBasicParsing -Headers @{ Cookie = $env:FORUM_COOKIE }
        $threads = $html.Links | Where-Object { $_.href -like "/threads/*" }
        Write-Host "DEBUG: Found $($threads.Count) threads in section"

        foreach ($t in $threads) {
            Write-Host "DEBUG: candidate href=[$($t.href)], text=[$($t.innerText)]"
        }

        # Lọc theo text có 'En/Ru' (bỏ ngoặc vuông), case-insensitive
        $candidates = $threads | Where-Object { $_.innerText -match "(?i)En/Ru" }
        Write-Host "DEBUG: candidates with En/Ru count=$($candidates.Count)"

        # Nếu nhiều → lấy mới nhất bằng cách ưu tiên text chứa vYY.MM.DD lớn nhất
        function Extract-DateTag([string]$text) {
          if ($text -match "v(\d{2}\.\d{2}\.\d{2})") { return $matches[1] } else { return "" }
        }
        $candidates = $candidates | Sort-Object @{Expression={ Extract-DateTag $_.innerText }; Ascending=$false}
        $thread = $candidates | Select-Object -First 1

        # Fallback: nếu không có En/Ru, chọn thread đầu tiên có từ khóa 'Windows 7' (hoặc dùng rules)
        if (-not $thread) {
          $fallback = $threads | Where-Object { $_.innerText -match "(?i)Windows\s*7" } | Select-Object -First 1
          if ($fallback) {
            Write-Host "DEBUG: Fallback thread by keyword Windows 7"
            $thread = $fallback
          }
        }

        if (-not $thread) { Write-Host "WARN: No matching thread in section"; continue }

        # Lấy filenameA từ slug thread
        $slugParts = $thread.href.Trim('/') -split '/'
        # /threads/<slug>.<id>/
        $slugRaw   = $slugParts[1]
        $filenameA = ($slugRaw -replace "\.\d+$","")
        Write-Host "DEBUG: filenameA from forum section=[$filenameA]"

        $threadUrl = "https://forum.rg-adguard.net$($thread.href)"
        Write-Host "DEBUG: threadUrl=[$threadUrl]"

        # Lấy goLink và resolve share
        $page   = Invoke-WebRequest $threadUrl -UseBasicParsing -Headers @{ Cookie = $env:FORUM_COOKIE }
        $goLink = ($page.Links | Where-Object { $_.href -like "https://go.rg-adguard.net/*" } | Select-Object -First 1).href
        if (-not $goLink) { Write-Host "WARN: No goLink"; continue }

        $resp      = Invoke-WebRequest $goLink -MaximumRedirection 0 -ErrorAction SilentlyContinue
        $shareLink = $resp.Headers["Location"]
        Write-Host "DEBUG: shareLink=[$shareLink]"
        if ([string]::IsNullOrWhiteSpace($shareLink)) { Write-Host "WARN: shareLink trống"; continue }

        $realLink  = (& php (Join-Path $env:REPO_PATH "downloader.php") $shareLink | Out-String).Trim()
        Write-Host "DEBUG: downloader output=[$realLink]"
    }
    # Forum thread trực tiếp
    elseif ($link -like "https://forum.rg-adguard.net/threads/*") {
        Write-Host "DEBUG: Forum thread detected"
        $threadUrl = $link
        $slugParts = $threadUrl.Trim('/') -split '/'
        $slugRaw   = $slugParts[2]
        $filenameA = ($slugRaw -replace "\.\d+$","")
        Write-Host "DEBUG: filenameA from forum thread=[$filenameA]"

        $page   = Invoke-WebRequest $threadUrl -UseBasicParsing -Headers @{ Cookie = $env:FORUM_COOKIE }
        $goLink = ($page.Links | Where-Object { $_.href -like "https://go.rg-adguard.net/*" } | Select-Object -First 1).href
        if (-not $goLink) { Write-Host "WARN: No goLink"; continue }

        $resp      = Invoke-WebRequest $goLink -MaximumRedirection 0 -ErrorAction SilentlyContinue
        $shareLink = $resp.Headers["Location"]
        Write-Host "DEBUG: shareLink=[$shareLink]"
        if ([string]::IsNullOrWhiteSpace($shareLink)) { Write-Host "WARN: shareLink trống"; continue }

        $realLink  = (& php (Join-Path $env:REPO_PATH "downloader.php") $shareLink | Out-String).Trim()
        Write-Host "DEBUG: downloader output=[$realLink]"
    }
    # Cloud share
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

    # Phân loại folder theo rules
    $folder = Resolve-Folder -FileNameA $filenameA

    # Check-exists
    $RawJson = (& (Join-Path $env:REPO_PATH "check-exists.ps1") -FileNameA $filenameA -Folder $folder | Out-String).Trim()
    Write-Host "DEBUG: check-exists raw=[$RawJson]"

    if ($RawJson.StartsWith("{")) {
        $Info = $RawJson | ConvertFrom-Json
        Write-Host "DEBUG: Parsed JSON status=[$($Info.status)], folder=[$folder], baseKey=[$($Info.baseKey)], dateTag=[$($Info.dateTag)], deleteList=[$($Info.deleteList)]"
        $pipeLine = "$($Info.status)|$realLink|$folder|$filenameA|$($Info.baseKey)|$($Info.dateTag)|$($Info.deleteList)"
        Write-Host "DEBUG: Write pipe=[$pipeLine]"
        Add-Content $pipePath $pipeLine
    } else {
        Write-Host "WARN: check-exists không trả JSON"
    }
}
