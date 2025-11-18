param(
    [string]$Mode
)

Write-Host "[DEBUG] prepare-build.ps1 started"
Write-Host "[DEBUG] MODE arg: $Mode"
Write-Host "[DEBUG] RCLONE_PATH=$env:RCLONE_PATH"
Write-Host "[DEBUG] ALIST_PATH=$env:ALIST_PATH"
Write-Host "[DEBUG] RCLONE_CONFIG_PATH=$env:RCLONE_CONFIG_PATH"

# Tạo thư mục local
foreach ($d in @("$env:SCRIPT_PATH\$env:iso",
                 "$env:SCRIPT_PATH\$env:driver",
                 "$env:SCRIPT_PATH\$env:boot7",
                 "$env:SCRIPT_PATH\$env:silent",
                 "$env:SCRIPT_PATH\$env:vietstar")) {
    if (-not (Test-Path $d)) {
        Write-Host "[DEBUG] mkdir $d"
        New-Item -ItemType Directory -Path $d | Out-Null
    }
}

# Đọc rule.env
$ruleFile = "$env:SCRIPT_PATH\rule.env"
if (-not (Test-Path $ruleFile)) {
    Write-Error "[ERROR] rule.env not found at $ruleFile"
    exit 1
}
$ruleMap = @{}
Get-Content $ruleFile | ForEach-Object {
    $parts = $_ -split '=',2
    if ($parts.Length -eq 2) { $ruleMap[$parts[0]] = $parts[1] }
}

Write-Host "[DEBUG] folder=$($ruleMap['folder'])"
Write-Host "[DEBUG] patterns=$($ruleMap['patterns'])"

# Lấy danh sách file bằng lsjson
if ($ruleMap['patterns']) {
    $remoteDir = "$($env:RCLONE_PATH)$($env:iso)/$($ruleMap['folder'])"
    Write-Host "[DEBUG] rclone lsjson $remoteDir --include $($ruleMap['patterns'])"

    try {
        $jsonMain = & "$env:SCRIPT_PATH\rclone.exe" lsjson $remoteDir `
            --config "$env:RCLONE_CONFIG_PATH" `
            --include "$($ruleMap['patterns'])" 2>$null
        if ($jsonMain) {
            $files = $jsonMain | ConvertFrom-Json
            $lastFile = $files | Select-Object -Last 1
            Write-Host "[DEBUG] fileA=$($lastFile.Name)"
            if ($lastFile) {
                $localDir = "$env:SCRIPT_PATH\$env:iso"
                $alistUrl = "$env:ALIST_PATH/$($env:iso)/$($ruleMap['folder'])/$($lastFile.Name)"
                Write-Host "[PREPARE] Download $($lastFile.Name)"
                aria2c -q -d $localDir $alistUrl
            }
        }
    } catch {
        Write-Error "[ERROR] rclone lsjson failed"
        exit 1
    }
}

Write-Host "[PREPARE] Env OK"
