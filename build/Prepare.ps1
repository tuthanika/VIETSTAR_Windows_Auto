param([string]$Mode)

Write-Host "=== Prepare start for $Mode ==="
Write-Host "[DEBUG] SCRIPT_PATH=$env:SCRIPT_PATH"

foreach ($d in @("$env:SCRIPT_PATH\$env:iso",
                 "$env:SCRIPT_PATH\$env:driver",
                 "$env:SCRIPT_PATH\$env:boot7",
                 "$env:SCRIPT_PATH\$env:silent")) {
    if (-not (Test-Path $d)) {
        Write-Host "[DEBUG] mkdir $d"
        New-Item -ItemType Directory -Path $d | Out-Null
    }
}

$ruleFile = "$env:SCRIPT_PATH\rule.env"
if (-not (Test-Path $ruleFile)) { Write-Error "[ERROR] rule.env not found"; exit 1 }

$ruleMap = @{}
Get-Content $ruleFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and $line -notmatch '^\s*#') {
        $parts = $line -split '=',2
        if ($parts.Length -eq 2) { $ruleMap[$parts[0]] = $parts[1] }
    }
}
Write-Host "[DEBUG] rule.env keys: $($ruleMap.Keys -join ', ')"

function Invoke-DownloadRule {
    param(
        [string]$folderName,
        [string]$patterns,
        [string]$localSubDir,
        [string]$label
    )

    if ([string]::IsNullOrWhiteSpace($folderName) -or [string]::IsNullOrWhiteSpace($patterns)) {
        Write-Host "[DEBUG][$label] Skip (not defined in env)"
        return $null
    }

    $remoteDir = "$($env:RCLONE_PATH)$($env:iso)/$folderName"
    Write-Host "[DEBUG][$label] rclone lsjson $remoteDir --include $patterns"

    try {
        $jsonMain = & "$env:SCRIPT_PATH\rclone.exe" lsjson $remoteDir `
            --config "$env:RCLONE_CONFIG_PATH" `
            --include "$patterns" 2>&1

        Write-Host "=== DEBUG[$label]: rclone raw output ==="
        Write-Host $jsonMain

        if ($jsonMain) {
            $files = $jsonMain | ConvertFrom-Json
            $lastFile = $files | Select-Object -Last 1
            if ($lastFile) {
                Write-Host "[DEBUG][$label] Found $($lastFile.Name) in $folderName"

                $alistPathRel = "/$($env:ALIST_PATH)/$($env:iso)/$folderName/$($lastFile.Name)"
                $apiUrl = "$($env:ALIST_HOST.TrimEnd('/'))/api/fs/get"
                $body = @{ path = $alistPathRel } | ConvertTo-Json -Compress

                Write-Host "[DEBUG][$label] Alist API url=$apiUrl"
                Write-Host "[DEBUG][$label] Alist API path=$alistPathRel"

                try {
                    $response = Invoke-RestMethod -Uri $apiUrl `
                        -Method Post `
                        -Headers @{ Authorization = $env:ALIST_TOKEN } `
                        -Body $body `
                        -ContentType "application/json" `
                        -ErrorAction Stop

                    Write-Host "=== DEBUG[$label]: Alist API response JSON (full) ==="
                    ($response | ConvertTo-Json -Depth 6 | Out-String) | Write-Host

                    $rawUrl = [string]$response.data.raw_url

                    Write-Host "[DEBUG][$label] raw_url length=$($rawUrl.Length)"
                    $tailLen = [Math]::Min(64, $rawUrl.Length)
                    Write-Host "[DEBUG][$label] raw_url tail[$tailLen]=" + $rawUrl.Substring($rawUrl.Length - $tailLen)
                    Write-Host "[DEBUG][$label] raw_url endsWith '&ApiVersion=2.0'=" + $rawUrl.EndsWith("&ApiVersion=2.0")

                    $rawFile = "$env:SCRIPT_PATH\raw_url.$label.txt"
                    $rawUrl | Out-File -FilePath $rawFile -Encoding utf8 -NoNewline
                    $rawFromFile = (Get-Content $rawFile -Raw)
                    Write-Host "[DEBUG][$label] raw_url.$label.txt length=$($rawFromFile.Length)"
                    $tailLenFile = [Math]::Min(64, $rawFromFile.Length)
                    Write-Host "[DEBUG][$label] raw_url.$label.txt tail[$tailLenFile]=" + $rawFromFile.Substring($rawFromFile.Length - $tailLenFile)
                    Write-Host "[DEBUG][$label] raw_url.$label.txt endsWith '&ApiVersion=2.0' (raw)=" + $rawFromFile.EndsWith("&ApiVersion=2.0")
                    Write-Host "[DEBUG][$label] raw_url.$label.txt endsWith '&ApiVersion=2.0' (trim)=" + $rawFromFile.TrimEnd().EndsWith("&ApiVersion=2.0")

                    $expectedPrefix = "$($env:ALIST_HOST.TrimEnd('/'))/$($env:ALIST_PATH)"
                    if ([string]::IsNullOrWhiteSpace($rawUrl)) {
                        Write-Warning "[WARN][$label] raw_url not found, fallback to direct URL"
                        $downloadUrl = "$expectedPrefix/$($env:iso)/$folderName/$($lastFile.Name)"
                    } elseif ($rawUrl.StartsWith($expectedPrefix)) {
                        Write-Host "[DEBUG][$label] raw_url is internal, rebuild direct URL"
                        $downloadUrl = "$expectedPrefix/$($env:iso)/$folderName/$($lastFile.Name)"
                    } else {
                        Write-Host "[DEBUG][$label] raw_url is external, keep as-is"
                        $downloadUrl = $rawUrl
                    }

                    Write-Host "[DEBUG][$label] downloadUrl length=$($downloadUrl.Length)"
                    $dlTailLen = [Math]::Min(64, $downloadUrl.Length)
                    Write-Host "[DEBUG][$label] downloadUrl tail[$dlTailLen]=" + $downloadUrl.Substring($downloadUrl.Length - $dlTailLen)
                    Write-Host "[DEBUG][$label] downloadUrl endsWith '&ApiVersion=2.0'=" + $downloadUrl.EndsWith("&ApiVersion=2.0")

                    $dlFile = "$env:SCRIPT_PATH\download_url.$label.txt"
                    $downloadUrl | Out-File -FilePath $dlFile -Encoding utf8 -NoNewline
                    $dlFromFile = (Get-Content $dlFile -Raw)
                    Write-Host "[DEBUG][$label] download_url.$label.txt length=$($dlFromFile.Length)"
                    $dlTailLenFile = [Math]::Min(64, $dlFromFile.Length)
                    Write-Host "[DEBUG][$label] download_url.$label.txt tail[$dlTailLenFile]=" + $dlFromFile.Substring($dlFromFile.Length - $dlTailLenFile)
                    Write-Host "[DEBUG][$label] download_url.$label.txt endsWith '&ApiVersion=2.0' (raw)=" + $dlFromFile.EndsWith("&ApiVersion=2.0")
                    Write-Host "[DEBUG][$label] download_url.$label.txt endsWith '&ApiVersion=2.0' (trim)=" + $dlFromFile.TrimEnd().EndsWith("&ApiVersion=2.0")

                    $localDir = "$env:SCRIPT_PATH\$localSubDir"
                    $ariaListFile = "$env:SCRIPT_PATH\aria2_urls.$label.txt"
                    $downloadUrl | Out-File -FilePath $ariaListFile -Encoding utf8 -NoNewline

                    Write-Host "[PREPARE][$label] Download $($lastFile.Name) from input-file: $ariaListFile"
                    $ariaFileRaw = Get-Content $ariaListFile -Raw
                    Write-Host "[DEBUG][$label] aria2 input file length=$($ariaFileRaw.Length)"
                    Write-Host "[DEBUG][$label] aria2 input file endsWith '&ApiVersion=2.0' (raw)=" + $ariaFileRaw.EndsWith("&ApiVersion=2.0")
                    Write-Host "[DEBUG][$label] aria2 input file endsWith '&ApiVersion=2.0' (trim)=" + $ariaFileRaw.TrimEnd().EndsWith("&ApiVersion=2.0")

                    $ariaLog = "$env:SCRIPT_PATH\aria2.$label.log"
                    $ariaOut = & aria2c `
                        -l "$ariaLog" `
                        --log-level=debug `
                        --file-allocation=none `
                        --max-connection-per-server=16 `
                        --split=16 `
                        --enable-http-keep-alive=false `
                        -d "$localDir" `
                        --input-file="$ariaListFile" 2>&1

                    Write-Host "=== DEBUG[$label]: aria2c output ==="
                    Write-Host $ariaOut
                    Write-Host "=== DEBUG[$label]: aria2c log tail ==="
                    if (Test-Path $ariaLog) { Get-Content "$ariaLog" -Tail 60 | ForEach-Object { Write-Host $_ } }

                    return "$localDir\$($lastFile.Name)"
                }
                catch {
                    Write-Warning "[WARN][$label] Alist API request failed: $($_.Exception.Message)"
                    return $null
                }
            } else {
                Write-Host "[DEBUG][$label] No file matched."
            }
        } else {
            Write-Host "[DEBUG][$label] rclone returned empty."
        }
    }
    catch {
        Write-Warning "[WARN][$label] rclone lsjson failed: $($_.Exception.Message)"
    }
    return $null
}

$results = @{}
$results['iso']    = Invoke-DownloadRule -folderName $ruleMap['folder']       -patterns $ruleMap['patterns']       -localSubDir $env:iso    -label "iso"
$results['driver'] = Invoke-DownloadRule -folderName $ruleMap['drvFolder']    -patterns $ruleMap['drvPatterns']    -localSubDir $env:driver -label "driver"
$results['boot7']  = Invoke-DownloadRule -folderName $ruleMap['bootFolder']   -patterns $ruleMap['bootPatterns']   -localSubDir $env:boot7  -label "boot7"
$results['silent'] = Invoke-DownloadRule -folderName $ruleMap['silentFolder'] -patterns $ruleMap['silentPatterns'] -localSubDir $env:silent -label "silent"

Write-Host "=== Prepare done for $Mode ==="
Write-Output $results
