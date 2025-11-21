param([string]$Mode)

Write-Host "=== Prepare start for $Mode ==="
Write-Host "[DEBUG] SCRIPT_PATH=$env:SCRIPT_PATH"

# Tạo thư mục local từ *_path (an toàn, không nhân đôi)
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

# Đọc rule.env
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

# Ghép remote path: base_path + (optional) subFolder
function Resolve-RemoteDir {
    param(
        [string]$basePath,   # ví dụ z.ISO, z.BOOT7, z.DRIVER, z.Silent, z.VIETSTAR
        [string]$subFolder   # thư mục con từ rule.env (có thể rỗng)
    )
    if ([string]::IsNullOrWhiteSpace($subFolder)) {
        return "$($env:RCLONE_PATH)$basePath"
    } else {
        return "$($env:RCLONE_PATH)$basePath/$subFolder"
    }
}

# Liệt kê từ remote và chọn file cuối cùng theo patterns
function Resolve-RemoteLatest {
    param(
        [string]$base,
        [string]$subFolder,
        [string]$patterns
    )
    if ([string]::IsNullOrWhiteSpace($patterns)) { return $null }

    $remoteDir = Resolve-RemoteDir -basePath $base -subFolder $subFolder
    Write-Host "[DEBUG] Resolve-RemoteLatest base=$base subFolder=$subFolder patterns=$patterns"
    Write-Host "[DEBUG] remoteDir=$remoteDir"

    try {
        $jsonOut = & "$env:SCRIPT_PATH\rclone.exe" lsjson $remoteDir `
            --config "$env:RCLONE_CONFIG_PATH" `
            --include "$patterns" 2>&1

        Write-Host "=== DEBUG: raw rclone output ==="
        $jsonOut | ForEach-Object { Write-Host "  $_" }

        # Cố gắng parse JSON, nếu lỗi thì coi như không có file
        try {
            $entries = $jsonOut | ConvertFrom-Json
        } catch {
            Write-Host "[DEBUG] ConvertFrom-Json failed: $($_.Exception.Message)"
            return $null
        }

        if (-not $entries) {
            Write-Host "[DEBUG] entries is null/empty"
            return $null
        }

        $files = @($entries | Where-Object { $_.IsDir -eq $false })
        Write-Host "[DEBUG] entries count=$($entries.Count), file entries=$($files.Count)"
        $files | ForEach-Object { Write-Host "  file: Name=$($_.Name) Size=$($_.Size) ModTime=$($_.ModTime)" }

        if (-not $files -or $files.Count -eq 0) { return $null }
        return ($files | Select-Object -Last 1)
    }
    catch {
        Write-Warning "[WARN] rclone lsjson failed: $($_.Exception.Message)"
        return $null
    }
}

# Lấy URL tải qua Alist (giữ nguyên logic raw_url / expectedPrefix)
function Get-DownloadUrl {
    param(
        [string]$base,        # *_path
        [string]$subFolder,   # từ rule.env: folder/drvFolder/bootFolder/silentFolder
        [string]$fileName
    )

    # Xây path tương đối dưới ALIST_PATH: /ALIST_PATH/base[/subFolder]/fileName
    $folderRel = if ([string]::IsNullOrWhiteSpace($subFolder)) { $base } else { "$base/$subFolder" }
    $alistPathRel = "/$($env:ALIST_PATH)/$folderRel/$fileName"
    $apiUrl = "$($env:ALIST_HOST.TrimEnd('/'))/api/fs/get"
    $body = @{ path = $alistPathRel } | ConvertTo-Json -Compress

    Write-Host "[DEBUG] Alist API url=$apiUrl"
    Write-Host "[DEBUG] Alist API path=$alistPathRel"

    try {
        $response = Invoke-RestMethod -Uri $apiUrl `
            -Method Post `
            -Headers @{ Authorization = $env:ALIST_TOKEN } `
            -Body $body `
            -ContentType "application/json" `
            -ErrorAction Stop

        Write-Host "=== DEBUG: Alist response ==="
        ($response | ConvertTo-Json -Depth 6 | Out-String) | Write-Host

        $rawUrl = [string]$response.data.raw_url
        Write-Host "[DEBUG] raw_url=$rawUrl"

        # Quyết định URL cuối
        $expectedPrefix = "$($env:ALIST_HOST.TrimEnd('/'))/$($env:ALIST_PATH)"
        if ([string]::IsNullOrWhiteSpace($rawUrl)) {
            Write-Warning "[WARN] raw_url empty, fallback to direct"
            return "$expectedPrefix/$folderRel/$fileName"
        } elseif ($rawUrl.StartsWith($expectedPrefix)) {
            Write-Host "[DEBUG] raw_url internal, rebuild direct"
            return "$expectedPrefix/$folderRel/$fileName"
        } else {
            Write-Host "[DEBUG] raw_url external, keep as-is"
            return $rawUrl
        }
    }
    catch {
        Write-Warning "[WARN] Alist API request failed: $($_.Exception.Message)"
        # Fallback direct URL
        $expectedPrefix = "$($env:ALIST_HOST.TrimEnd('/'))/$($env:ALIST_PATH)"
        return "$expectedPrefix/$folderRel/$fileName"
    }
}

function Invoke-DownloadGroup {
    param(
        [string]$label,
        [string]$base,
        [string]$subFolder,
        [string]$patterns,
        [string]$localDir
    )

    Write-Host "[DEBUG][$label] base=$base subFolder=$subFolder patterns=$patterns localDir=$localDir"

    if ([string]::IsNullOrWhiteSpace($patterns)) {
        Write-Host "[DEBUG][$label] Skip (no patterns)"
        return $null
    }

    $latest = Resolve-RemoteLatest -base $base -subFolder $subFolder -patterns $patterns
    if (-not $latest) {
        Write-Host "[DEBUG][$label] No matching files found."
        return $null
    }

    Write-Host "[DEBUG][$label] Selected file=$($latest.Name) size=$($latest.Size)"
    $localFile = Join-Path $localDir $latest.Name

    # Kiểm tra file local trước khi tải
    if (Test-Path $localFile) {
        $localSize = (Get-Item $localFile).Length
        Write-Host "[DEBUG][$label] Local file exists: $localFile size=$localSize, remote size=$($latest.Size)"
        if ($localSize -eq $latest.Size) {
            Write-Host "[DEBUG][$label] Local file matches remote size, skip download."
            return $localFile
        } else {
            Write-Host "[DEBUG][$label] Local file size mismatch, will re-download."
        }
    }

    # Nếu chưa có hoặc size khác thì tải về
    $downloadUrl = Get-DownloadUrl -base $base -subFolder $subFolder -fileName $latest.Name
    $ariaListFile = Join-Path $env:SCRIPT_PATH "aria2_urls.$label.txt"
    $ariaLog      = Join-Path $env:SCRIPT_PATH "aria2.$label.log"
    $downloadUrl | Out-File -FilePath $ariaListFile -Encoding utf8 -NoNewline

    Write-Host "[PREPARE][$label] Download $($latest.Name) from: $downloadUrl"
    Write-Host "[DEBUG][$label] aria2 input=$ariaListFile log=$ariaLog"

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
    $ariaOut | ForEach-Object { Write-Host $_ }
    if (Test-Path $ariaLog) { Get-Content $ariaLog -Tail 40 | ForEach-Object { Write-Host $_ } }

    return $localFile
}

# Lấy subFolder/patterns từ rule.env theo đúng chuẩn bạn yêu cầu
$isoFolder       = $ruleMap['folder']        # ISO/Vietstar ghép thêm Folder
$isoPatterns     = $ruleMap['patterns']

$drvFolder       = $ruleMap['drvFolder']     # Driver: nếu có thì base/DriverFolder, không thì base
$drvPatterns     = $ruleMap['drvPatterns']

$bootFolder      = $ruleMap['bootFolder']    # Boot: nếu có thì base/BootFolder, không thì base
$bootPatterns    = $ruleMap['bootPatterns']

$silentFolder    = $ruleMap['silentFolder']  # Silent: nếu có thì base/SilentFolder, không thì base
$silentPatterns  = $ruleMap['silentPatterns']

Write-Host "[DEBUG] ISO folder=$isoFolder patterns=$isoPatterns"
Write-Host "[DEBUG] DRIVER folder=$drvFolder patterns=$drvPatterns"
Write-Host "[DEBUG] BOOT7 folder=$bootFolder patterns=$bootPatterns"
Write-Host "[DEBUG] SILENT folder=$silentFolder patterns=$silentPatterns"

$results = @{
    iso    = Invoke-DownloadGroup -label "iso"    -base $env:iso_path    -subFolder $isoFolder    -patterns $isoPatterns     -localDir $isoDir
    driver = Invoke-DownloadGroup -label "driver" -base $env:driver_path -subFolder $drvFolder    -patterns $drvPatterns     -localDir $driverDir
    boot7  = Invoke-DownloadGroup -label "boot7"  -base $env:boot7_path  -subFolder $bootFolder   -patterns $bootPatterns    -localDir $boot7Dir
    silent = Invoke-DownloadGroup -label "silent" -base $env:silent_path -subFolder $silentFolder -patterns $silentPatterns  -localDir $silentDir
}

Write-Output $results
