param([string]$Mode)

Write-Host "=== DEBUG: prepare-build.ps1 started ==="
Write-Host "[DEBUG] MODE arg: $Mode"
Write-Host "[DEBUG] SCRIPT_PATH=$env:SCRIPT_PATH"
Write-Host "[DEBUG] RCLONE_PATH=$env:RCLONE_PATH"
Write-Host "[DEBUG] ALIST_HOST=$env:ALIST_HOST"
Write-Host "[DEBUG] ALIST_PATH=$env:ALIST_PATH"
Write-Host "[DEBUG] ALIST_TOKEN set? " -NoNewline; Write-Host ([string]::IsNullOrEmpty($env:ALIST_TOKEN) ? "NO" : "YES")
Write-Host "[DEBUG] RCLONE_CONFIG_PATH=$env:RCLONE_CONFIG_PATH"

# Tạo thư mục local
foreach ($d in @("$env:SCRIPT_PATH\$env:iso",
                 "$env:SCRIPT_PATH\$env:vietstar",
                 "$env:SCRIPT_PATH\$env:driver",
                 "$env:SCRIPT_PATH\$env:boot7",
                 "$env:SCRIPT_PATH\$env:silent")) {
    if (-not (Test-Path $d)) {
        Write-Host "[DEBUG] mkdir $d"
        New-Item -ItemType Directory -Path $d | Out-Null
    }
}

# Đọc rule.env
$ruleFile = "$env:SCRIPT_PATH\rule.env"
Write-Host "[DEBUG] Reading rule file: $ruleFile"
if (-not (Test-Path $ruleFile)) { Write-Error "[ERROR] rule.env not found"; exit 1 }

$ruleMap = @{}
Get-Content $ruleFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and $line -notmatch '^\s*#') {
        $parts = $line -split '=',2
        if ($parts.Length -eq 2) { $ruleMap[$parts[0]] = $parts[1] }
    }
}
Write-Host "[DEBUG] folder=$($ruleMap['folder'])"
Write-Host "[DEBUG] patterns=$($ruleMap['patterns'])"

# Tìm file bằng rclone lsjson
if ($ruleMap['patterns']) {
    $remoteDir = "$($env:RCLONE_PATH)$($env:iso)/$($ruleMap['folder'])"
    Write-Host "[DEBUG] rclone lsjson $remoteDir --include $($ruleMap['patterns'])"

    try {
        $jsonMain = & "$env:SCRIPT_PATH\rclone.exe" lsjson $remoteDir `
            --config "$env:RCLONE_CONFIG_PATH" `
            --include "$($ruleMap['patterns'])" 2>&1

        Write-Host "=== DEBUG: rclone raw output ==="
        Write-Host $jsonMain

        if ($jsonMain) {
            $files = $jsonMain | ConvertFrom-Json
            Write-Host "=== DEBUG: Files found ==="
            $files | ForEach-Object { Write-Host "  $($_.Name)" }

            $lastFile = $files | Select-Object -Last 1
            Write-Host "[DEBUG] fileA=$($lastFile.Name)"

            if ($lastFile) {
                $alistPathRel = "/$($env:ALIST_PATH)/$($env:iso)/$($ruleMap['folder'])/$($lastFile.Name)"
                $apiUrl = "$($env:ALIST_HOST.TrimEnd('/'))/api/fs/get"
                $body = @{ path = $alistPathRel } | ConvertTo-Json -Compress

                Write-Host "[DEBUG] Alist API url=$apiUrl"
                Write-Host "[DEBUG] Alist API path=$alistPathRel"

                $downloadUrl = $null
try {
    $response = Invoke-RestMethod -Uri $apiUrl `
        -Method Post `
        -Headers @{ Authorization = $env:ALIST_TOKEN } `
        -Body $body `
        -ContentType "application/json" `
        -ErrorAction Stop

    Write-Host "=== DEBUG: Alist API response JSON (full) ==="
    ($response | ConvertTo-Json -Depth 6 | Out-String) | Write-Host

    # 1) Lấy raw_url và ép kiểu string ngay
    $rawUrl = [string]$response.data.raw_url

    # Console debug: length, tail, marker
    Write-Host "[DEBUG] raw_url (console)=$rawUrl"
    Write-Host "[DEBUG] raw_url length=$($rawUrl.Length)"
    $tailLen = [Math]::Min(64, $rawUrl.Length)
    Write-Host "[DEBUG] raw_url tail[$tailLen]=" + $rawUrl.Substring($rawUrl.Length - $tailLen)
    Write-Host "[DEBUG] raw_url endsWith '&ApiVersion=2.0'=" + $rawUrl.EndsWith("&ApiVersion=2.0")

    # 2) Ghi ra file KHÔNG thêm newline
    $rawFile = "$env:SCRIPT_PATH\raw_url.txt"
    $rawUrl | Out-File -FilePath $rawFile -Encoding utf8 -NoNewline

    # Đọc lại và trim cuối để kiểm tra
    $rawFromFile = (Get-Content $rawFile -Raw)
    $rawFromFileTrim = $rawFromFile.TrimEnd()

    Write-Host "[DEBUG] raw_url.txt length=$($rawFromFile.Length)"
    $tailLenFile = [Math]::Min(64, $rawFromFile.Length)
    Write-Host "[DEBUG] raw_url.txt tail[$tailLenFile]=" + $rawFromFile.Substring($rawFromFile.Length - $tailLenFile)
    Write-Host "[DEBUG] raw_url.txt endsWith '&ApiVersion=2.0' (raw)=" + $rawFromFile.EndsWith("&ApiVersion=2.0")
    Write-Host "[DEBUG] raw_url.txt endsWith '&ApiVersion=2.0' (trim)=" + $rawFromFileTrim.EndsWith("&ApiVersion=2.0")

    # Hash để so sánh tính toàn vẹn giữa biến và file (trim)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $rawHashMem = [System.BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($rawUrl))).Replace("-", "")
    $rawHashFile = [System.BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($rawFromFileTrim))).Replace("-", "")
    Write-Host "[DEBUG] raw_url SHA256 (mem)=$rawHashMem"
    Write-Host "[DEBUG] raw_url SHA256 (file-trim)=$rawHashFile"
    Write-Host "[DEBUG] raw_url mem==file-trim:" ($rawHashMem -eq $rawHashFile)

    # 3) Giữ logic nội bộ như bạn yêu cầu
    $expectedPrefix = "$($env:ALIST_HOST.TrimEnd('/'))/$($env:ALIST_PATH)"
    if ([string]::IsNullOrWhiteSpace($rawUrl)) {
        Write-Warning "[WARN] raw_url not found, fallback to direct URL"
        $downloadUrl = "$expectedPrefix/$($env:iso)/$($ruleMap['folder'])/$($lastFile.Name)"
    } elseif ($rawUrl.StartsWith($expectedPrefix)) {
        Write-Host "[DEBUG] raw_url is internal, rebuild direct URL"
        $downloadUrl = "$expectedPrefix/$($env:iso)/$($ruleMap['folder'])/$($lastFile.Name)"
    } else {
        Write-Host "[DEBUG] raw_url is external, keep as-is"
        $downloadUrl = $rawUrl
    }

    # 4) Debug downloadUrl tương tự
    Write-Host "[DEBUG] downloadUrl (console)=$downloadUrl"
    Write-Host "[DEBUG] downloadUrl length=$($downloadUrl.Length)"
    $dlTailLen = [Math]::Min(64, $downloadUrl.Length)
    Write-Host "[DEBUG] downloadUrl tail[$dlTailLen]=" + $downloadUrl.Substring($downloadUrl.Length - $dlTailLen)
    Write-Host "[DEBUG] downloadUrl endsWith '&ApiVersion=2.0'=" + $downloadUrl.EndsWith("&ApiVersion=2.0")

    $dlFile = "$env:SCRIPT_PATH\download_url.txt"
    $downloadUrl | Out-File -FilePath $dlFile -Encoding utf8 -NoNewline
    $dlFromFile = (Get-Content $dlFile -Raw)
    $dlFromFileTrim = $dlFromFile.TrimEnd()

    Write-Host "[DEBUG] download_url.txt length=$($dlFromFile.Length)"
    $dlTailLenFile = [Math]::Min(64, $dlFromFile.Length)
    Write-Host "[DEBUG] download_url.txt tail[$dlTailLenFile]=" + $dlFromFile.Substring($dlFromFile.Length - $dlTailLenFile)
    Write-Host "[DEBUG] download_url.txt endsWith '&ApiVersion=2.0' (raw)=" + $dlFromFile.EndsWith("&ApiVersion=2.0")
    Write-Host "[DEBUG] download_url.txt endsWith '&ApiVersion=2.0' (trim)=" + $dlFromFileTrim.EndsWith("&ApiVersion=2.0")

    $dlHashMem = [System.BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($downloadUrl))).Replace("-", "")
    $dlHashFile = [System.BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($dlFromFileTrim))).Replace("-", "")
    Write-Host "[DEBUG] downloadUrl SHA256 (mem)=$dlHashMem"
    Write-Host "[DEBUG] downloadUrl SHA256 (file-trim)=$dlHashFile"
    Write-Host "[DEBUG] downloadUrl mem==file-trim:" ($dlHashMem -eq $dlHashFile)

    # 5) Cho aria2c đọc URL từ file input (1 dòng, không newline)
    $localDir = "$env:SCRIPT_PATH\$env:iso"
    $ariaListFile = "$env:SCRIPT_PATH\aria2_urls.txt"
    $downloadUrl | Out-File -FilePath $ariaListFile -Encoding utf8 -NoNewline

    Write-Host "[PREPARE] Download $($lastFile.Name) from input-file: $ariaListFile"
    $ariaFileRaw = Get-Content $ariaListFile -Raw
    Write-Host "[DEBUG] aria2 input file length=$($ariaFileRaw.Length)"
    Write-Host "[DEBUG] aria2 input file endsWith '&ApiVersion=2.0' (raw)=" + $ariaFileRaw.EndsWith("&ApiVersion=2.0")
    Write-Host "[DEBUG] aria2 input file endsWith '&ApiVersion=2.0' (trim)=" + $ariaFileRaw.TrimEnd().EndsWith("&ApiVersion=2.0")

    $ariaLog = "$env:SCRIPT_PATH\aria2.log"
    $ariaOut = & aria2c `
        -l "$ariaLog" `
        --log-level=debug `
		--file-allocation=none `
        --max-connection-per-server=16 `
		--split=16 `
		--enable-http-keep-alive=false `
        -d "$localDir" `
        --input-file="$ariaListFile" 2>&1

    Write-Host "=== DEBUG: aria2c output ==="
    Write-Host $ariaOut
    Write-Host "=== DEBUG: aria2c log tail ==="
    if (Test-Path $ariaLog) { Get-Content "$ariaLog" -Tail 80 | ForEach-Object { Write-Host $_ } }
}
catch {
    Write-Warning "[WARN] Alist API request failed: $($_.Exception.Message)"
}

            } # đóng if ($lastFile)
        } else {
            Write-Host "[DEBUG] No files matched pattern"
        } # đóng if ($jsonMain)
    }
    catch {
        Write-Warning "[WARN] rclone lsjson failed: $_"
    }
} # đóng if ($ruleMap['patterns'])

Write-Host "=== DEBUG: prepare-build.ps1 finished ==="
exit 0
