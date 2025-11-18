param([string]$Mode)

Write-Host "=== DEBUG: prepare-build.ps1 started ==="
Write-Host "[DEBUG] MODE arg: $Mode"
Write-Host "[DEBUG] SCRIPT_PATH=$env:SCRIPT_PATH"
Write-Host "[DEBUG] RCLONE_PATH=$env:RCLONE_PATH"
Write-Host "[DEBUG] ALIST_PATH=$env:ALIST_PATH"
Write-Host "[DEBUG] ALIST_TOKEN=$env:ALIST_TOKEN"
Write-Host "[DEBUG] RCLONE_CONFIG_PATH=$env:RCLONE_CONFIG_PATH"

# Tạo thư mục local
foreach ($d in @("$env:SCRIPT_PATH\$env:iso",
                 "$env:SCRIPT_PATH\$env:driver",
                 "$env:SCRIPT_PATH\$env:boot7",
                 "$env:SCRIPT_PATH\$env:silent",
                 "$env:SCRIPT_PATH\$env:vietstar")) {
    Write-Host "[DEBUG] mkdir $d"
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
}

# Đọc rule.env
$ruleFile = "$env:SCRIPT_PATH\rule.env"
Write-Host "[DEBUG] Reading rule file: $ruleFile"
if (-not (Test-Path $ruleFile)) { Write-Error "[ERROR] rule.env not found"; exit 1 }

$ruleMap = @{}
Get-Content $ruleFile | ForEach-Object {
    $parts = $_ -split '=',2
    if ($parts.Length -eq 2) { $ruleMap[$parts[0]] = $parts[1] }
}
Write-Host "[DEBUG] folder=$($ruleMap['folder'])"
Write-Host "[DEBUG] patterns=$($ruleMap['patterns'])"

# Lấy danh sách file bằng rclone lsjson
if ($ruleMap['patterns']) {
    $remoteDir = "$($env:RCLONE_PATH)$($env:iso)/$($ruleMap['folder'])"
    Write-Host "[DEBUG] rclone lsjson $remoteDir --include $($ruleMap['patterns'])"

    try {
        $jsonMain = & "$env:SCRIPT_PATH\rclone.exe" lsjson $remoteDir `
            --config "$env:RCLONE_CONFIG_PATH" `
            --include "$($ruleMap['patterns'])"

        Write-Host "=== DEBUG: rclone raw output ==="
        Write-Host $jsonMain

        if ($jsonMain) {
            $files = $jsonMain | ConvertFrom-Json
            Write-Host "=== DEBUG: Files found ==="
            $files | ForEach-Object { Write-Host "  $($_.Name)" }

            $lastFile = $files | Select-Object -Last 1
            Write-Host "[DEBUG] fileA=$($lastFile.Name)"

            if ($lastFile) {
                $localDir = "$env:SCRIPT_PATH\$env:iso"
                $alistUrl = "$env:ALIST_PATH/$($env:iso)/$($ruleMap['folder'])/$($lastFile.Name)"
                Write-Host "[PREPARE] Download $($lastFile.Name) from $alistUrl"

                # Dùng aria2c với Authorization header
                $ariaOut = & aria2c --header="Authorization: $env:ALIST_TOKEN" -d $localDir $alistUrl
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
