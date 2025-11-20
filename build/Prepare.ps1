param([string]$Mode)

Write-Host "=== Prepare start for $Mode ==="
Write-Host "[DEBUG] SCRIPT_PATH=$env:SCRIPT_PATH"

# Resolve local directories an toàn bằng Join-Path
$isoDir    = Join-Path $env:SCRIPT_PATH $env:iso
$driverDir = Join-Path $env:SCRIPT_PATH $env:driver
$boot7Dir  = Join-Path $env:SCRIPT_PATH $env:boot7
$silentDir = Join-Path $env:SCRIPT_PATH $env:silent

foreach ($d in @($isoDir, $driverDir, $boot7Dir, $silentDir)) {
    if (-not (Test-Path -LiteralPath $d)) {
        Write-Host "[DEBUG] mkdir $d"
        New-Item -ItemType Directory -Path $d | Out-Null
    }
}

$ruleFile = Join-Path $env:SCRIPT_PATH "rule.env"
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

function Get-RemoteDir {
    param(
        [string]$baseVal,
        [string]$folderName
    )
    if ([string]::IsNullOrWhiteSpace($folderName)) {
        return "$($env:RCLONE_PATH)$baseVal"
    }
    if ($folderName -eq $baseVal -or $folderName.StartsWith("$baseVal/")) {
        return "$($env:RCLONE_PATH)$folderName"
    }
    return "$($env:RCLONE_PATH)$baseVal/$folderName"
}

function Get-AlistRelPath {
    param(
        [string]$alistBase,
        [string]$folderName,
        [string]$fileName
    )
    $folderRel =
        if ([string]::IsNullOrWhiteSpace($folderName)) { $alistBase }
        elseif ($folderName -eq $alistBase) { $alistBase }
        elseif ($folderName.StartsWith("$alistBase/")) { $folderName }
        else { "$alistBase/$folderName" }

    return "/$($env:ALIST_PATH)/$folderRel/$fileName"
}

function Invoke-DownloadRule {
    param(
        [string]$folderName,
        [string]$patterns,
        [string]$localSubDirValue,
        [string]$label,
        [string]$baseEnvVar
    )

    if ([string]::IsNullOrWhiteSpace($folderName) -or [string]::IsNullOrWhiteSpace($patterns)) {
        Write-Host "[DEBUG][$label] Skip (not defined in env)"
        return $null
    }

    $baseVal = (Get-Item "env:$baseEnvVar").Value
    $remoteDir = Get-RemoteDir -baseVal $baseVal -folderName $folderName
    Write-Host "[DEBUG][$label] remoteDir=$remoteDir"
    Write-Host "[DEBUG][$label] rclone lsjson $remoteDir --include $patterns"

    try {
        $jsonMain = & "$env:SCRIPT_PATH\rclone.exe" lsjson $remoteDir `
            --config "$env:RCLONE_CONFIG_PATH" `
            --include "$patterns" 2>&1

        Write-Host "=== DEBUG[$label]: rclone raw output ==="
        Write-Host $jsonMain

        if ($jsonMain -match '^\s*\[') {
            $entries = $jsonMain | ConvertFrom-Json
            $fileEntries = @($entries | Where-Object { $_.IsDir -eq $false })
            if (-not $fileEntries -or $fileEntries.Count -eq 0) {
                Write-Host "[DEBUG][$label] No file entries after filtering IsDir=false."
                return $null
            }

            $lastFile = $fileEntries | Select-Object -Last 1
            Write-Host "[DEBUG][$label] Found file $($lastFile.Name) in $folderName"

            $alistPathRel = Get-AlistRelPath -alistBase $baseVal -folderName $folderName -fileName $lastFile.Name
            $apiUrl = "$($env:ALIST_HOST.TrimEnd('/'))/api/fs/get"
            $body = @{ path = $alistPathRel } | ConvertTo-Json -Compress

            try {
                $response = Invoke-RestMethod -Uri $apiUrl `
                    -Method Post `
                    -Headers @{ Authorization = $env:ALIST_TOKEN } `
                    -Body $body `
                    -ContentType "application/json" `
                    -ErrorAction Stop

                $rawUrl = [string]$response.data.raw_url
                $expectedPrefix = "$($env:ALIST_HOST.TrimEnd('/'))/$($env:ALIST_PATH)"
                if ([string]::IsNullOrWhiteSpace($rawUrl)) {
                    $downloadUrl = "$expectedPrefix/$((Get-AlistRelPath -alistBase $baseVal -folderName $folderName -fileName $lastFile.Name).TrimStart('/'))"
                } elseif ($rawUrl.StartsWith($expectedPrefix)) {
                    $downloadUrl = "$expectedPrefix/$((Get-AlistRelPath -alistBase $baseVal -folderName $folderName -fileName $lastFile.Name).Split('/',3)[2])"
                } else {
                    $downloadUrl = $rawUrl
                }

                $localDir = Join-Path $env:SCRIPT_PATH $localSubDirValue
                $ariaListFile = Join-Path $env:SCRIPT_PATH "aria2_urls.$label.txt"
                $downloadUrl | Out-File -FilePath $ariaListFile -Encoding utf8 -NoNewline

                Write-Host "[PREPARE][$label] Download $($lastFile.Name) from input-file: $ariaListFile"
                $ariaLog = Join-Path $env:SCRIPT_PATH "aria2.$label.log"
                & aria2c `
                    -l "$ariaLog" `
                    --log-level=info `
                    --file-allocation=none `
                    --max-connection-per-server=16 `
                    --split=16 `
                    --enable-http-keep-alive=false `
                    -d "$localDir" `
                    --input-file="$ariaListFile"

                if (Test-Path $ariaLog) { Get-Content $ariaLog -Tail 60 | ForEach-Object { Write-Host $_ } }

                return (Join-Path $localDir $lastFile.Name)
            }
            catch {
                Write-Warning "[WARN][$label] Alist API request failed: $($_.Exception.Message)"
                return $null
            }
        } else {
            Write-Warning "[WARN][$label] rclone output is not JSON; skip parsing."
        }
    }
    catch {
        Write-Warning "[WARN][$label] rclone lsjson failed: $($_.Exception.Message)"
    }
    return $null
}

$results = @{
    iso    = Invoke-DownloadRule -folderName $ruleMap['folder']       -patterns $ruleMap['patterns']       -localSubDirValue $env:iso    -label "iso"    -baseEnvVar "iso"
    driver = Invoke-DownloadRule -folderName $ruleMap['drvFolder']    -patterns $ruleMap['drvPatterns']    -localSubDirValue $env:driver -label "driver" -baseEnvVar "driver"
    boot7  = Invoke-DownloadRule -folderName $ruleMap['bootFolder']   -patterns $ruleMap['bootPatterns']   -localSubDirValue $env:boot7  -label "boot7"  -baseEnvVar "boot7"
    silent = Invoke-DownloadRule -folderName $ruleMap['silentFolder'] -patterns $ruleMap['silentPatterns'] -localSubDirValue $env:silent -label "silent" -baseEnvVar "silent"
}

Write-Output $results
