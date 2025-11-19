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

                    Write-Host "=== DEBUG: Alist API response JSON ==="
                    $response | ConvertTo-Json -Depth 6 | Write-Host

                    $downloadUrl = $response.data.raw_url
                } catch {
                    Write-Warning "[WARN] Alist API request failed: $($_.Exception.Message)"
                }

                if ([string]::IsNullOrWhiteSpace($downloadUrl)) {
                    Write-Warning "[WARN] raw_url not found, fallback to direct URL"
                    $downloadUrl = "$($env:ALIST_HOST.TrimEnd('/'))/$($env:ALIST_PATH)/$($env:iso)/$($ruleMap['folder'])/$($lastFile.Name)"
                }
				Write-Host "[DEBUG] raw_url length=$($downloadUrl.Length)"
                Write-Host "[PREPARE] Download $($lastFile.Name) from $downloadUrl"
                $localDir = "$env:SCRIPT_PATH\$env:iso"
				$ariaOut = & aria2c --header="Authorization: $env:ALIST_TOKEN" -d $localDir "$downloadUrl" 2>&1
                Write-Host "=== DEBUG: aria2c output ==="
                Write-Host $ariaOut
            }
        } else {
            Write-Host "[DEBUG] No files matched pattern"
        }
    } catch {
        Write-Warning "[WARN] rclone lsjson failed: $_"
    }
}

Write-Host "=== DEBUG: prepare-build.ps1 finished ==="
exit 0
