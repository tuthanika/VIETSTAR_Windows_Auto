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

# Chọn file iso
if ($ruleMap['patterns']) {
    $remote = "$($env:RCLONE_PATH)$($env:iso)/$($ruleMap['folder'])"
    Write-Host "[DEBUG] rclone ls $remote --include $($ruleMap['patterns'])"

    $list = & $env:SCRIPT_PATH\rclone.exe `
        --config $env:RCLONE_CONFIG_PATH `
        $env:rclone_flag `
        ls "$remote" --include "$($ruleMap['patterns'])"

    if ($LASTEXITCODE -ne 0) {
        Write-Error "[ERROR] rclone ls failed (exit=$LASTEXITCODE)"
        exit 1
    }

    $lastFile = ($list | ForEach-Object { ($_ -split '\s+',2)[1] }) | Select-Object -Last 1
    Write-Host "[DEBUG] fileA=$lastFile"

    if ($lastFile) {
        $localDir = "$env:SCRIPT_PATH\$env:iso"
        $alistUrl = "$env:ALIST_PATH/$($env:iso)/$($ruleMap['folder'])/$lastFile"
        Write-Host "[PREPARE] Download $lastFile"
        aria2c -q -d $localDir $alistUrl
    }
}

Write-Host "[PREPARE] Env OK"
