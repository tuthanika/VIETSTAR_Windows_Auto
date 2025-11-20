param([string]$Mode)

Write-Host "=== Prepare start for $Mode ==="
Write-Host "[DEBUG] SCRIPT_PATH=$env:SCRIPT_PATH"

# Local dirs using *_path (safe regardless of values)
$isoDir    = Join-Path $env:SCRIPT_PATH $env:iso_path
$driverDir = Join-Path $env:SCRIPT_PATH $env:driver_path
$boot7Dir  = Join-Path $env:SCRIPT_PATH $env:boot7_path
$silentDir = Join-Path $env:SCRIPT_PATH $env:silent_path

foreach ($d in @($isoDir, $driverDir, $boot7Dir, $silentDir)) {
    if (-not (Test-Path -LiteralPath $d)) {
        Write-Host "[DEBUG] mkdir $d"
        New-Item -ItemType Directory -Path $d | Out-Null
    }
}

# Read rule.env
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

# Helper: list and pick latest file by pattern from remote base and folder
function Resolve-RemoteLatest {
    param(
        [string]$base,      # e.g. z.ISO, z.DRIVER, z.BOOT7, z.Silent
        [string]$folder,    # e.g. Windows 7
        [string]$patterns   # semicolon patterns
    )
    if ([string]::IsNullOrWhiteSpace($patterns)) { return $null }
    $remoteDir = "$($env:RCLONE_PATH)$base/$folder"
    Write-Host "[DEBUG] rclone lsjson $remoteDir --include $patterns"

    try {
        $jsonOut = & "$env:SCRIPT_PATH\rclone.exe" lsjson $remoteDir `
            --config "$env:RCLONE_CONFIG_PATH" `
            --include "$patterns" 2>&1

        if (-not $jsonOut -or ($jsonOut -notmatch '^\s*\[')) {
            Write-Host "[DEBUG] rclone lsjson returned no JSON."
            return $null
        }
        $entries = $jsonOut | ConvertFrom-Json
        $files = @($entries | Where-Object { $_.IsDir -eq $false })
        if (-not $files -or $files.Count -eq 0) { return $null }
        return ($files | Select-Object -Last 1)
    }
    catch {
        Write-Warning "[WARN] rclone lsjson failed: $($_.Exception.Message)"
        return $null
    }
}

# Helper: build download URL via Alist for a given base/folder/file
function Get-DownloadUrl {
    param(
        [string]$base,
        [string]$folder,
        [string]$fileName
    )
    $alistPathRel = "/$($env:ALIST_PATH)/$base/$folder/$fileName"
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
            return "$expectedPrefix/$base/$folder/$fileName"
        } elseif ($rawUrl.StartsWith($expectedPrefix)) {
            return "$expectedPrefix/$base/$folder/$fileName"
        } else {
            return $rawUrl
        }
    }
    catch {
        Write-Warning "[WARN] Alist API request failed: $($_.Exception.Message)"
        return $null
    }
}

function Invoke-DownloadGroup {
    param(
        [string]$label,           # iso | driver | boot7 | silent
        [string]$base,            # *_path value (e.g. z.ISO)
        [string]$folder,          # from rule.env
        [string]$patterns,        # from rule.env
        [string]$localDir         # resolved local dir
    )

    if ([string]::IsNullOrWhiteSpace($folder) -or [string]::IsNullOrWhiteSpace($patterns)) {
        Write-Host "[DEBUG][$label] Skip (not defined in rule)"
        return $null
    }

    $latest = Resolve-RemoteLatest -base $base -folder $folder -patterns $patterns
    if (-not $latest) {
        Write-Host "[DEBUG][$label] No matching files found."
        return $null
    }

    Write-Host "[DEBUG][$label] Found file $($latest.Name) in $folder"
    $dlUrl = Get-DownloadUrl -base $base -folder $folder -fileName $latest.Name
    if (-not $dlUrl) { return $null }

    $ariaListFile = Join-Path $env:SCRIPT_PATH "aria2_urls.$label.txt"
    $ariaLog = Join-Path $env:SCRIPT_PATH "aria2.$label.log"

    $dlUrl | Out-File -FilePath $ariaListFile -Encoding utf8 -NoNewline
    Write-Host "[PREPARE][$label] Download $($latest.Name) from input-file: $ariaListFile"

    # Stream aria2c logs realtime
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

    return (Join-Path $localDir $latest.Name)
}

$results = @{
    iso    = Invoke-DownloadGroup -label "iso"    -base $env:iso_path    -folder $ruleMap['folder']       -patterns $ruleMap['patterns']       -localDir $isoDir
    driver = Invoke-DownloadGroup -label "driver" -base $env:driver_path -folder $ruleMap['drvFolder']    -patterns $ruleMap['drvPatterns']    -localDir $driverDir
    boot7  = Invoke-DownloadGroup -label "boot7"  -base $env:boot7_path  -folder $ruleMap['bootFolder']   -patterns $ruleMap['bootPatterns']   -localDir $boot7Dir
    silent = Invoke-DownloadGroup -label "silent" -base $env:silent_path -folder $ruleMap['silentFolder'] -patterns $ruleMap['silentPatterns'] -localDir $silentDir
}

Write-Output $results
