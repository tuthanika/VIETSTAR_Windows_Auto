param(
    [string]$Mode
)

Write-Host "[DEBUG] upload-build.ps1 started"
Write-Host "[DEBUG] MODE arg: $Mode"

$RC = "$env:SCRIPT_PATH\rclone.exe --config $env:RCLONE_CONFIG_PATH $env:rclone_flag"

$ruleFile = "$env:SCRIPT_PATH\rule.env"
if (-not (Test-Path $ruleFile)) {
    Write-Error "[ERROR] rule.env not found at $ruleFile"
    exit 1
}
$rules = Get-Content $ruleFile | ForEach-Object {
    $parts = $_ -split '=',2
    if ($parts.Length -eq 2) { @{ Key=$parts[0]; Value=$parts[1] } }
}
$ruleMap = @{}
foreach ($r in $rules) { $ruleMap[$r.Key] = $r.Value }

$folder = $ruleMap['folder']
if (-not $folder) {
    Write-Error "[ERROR] folder is empty in rule.env"
    exit 1
}

$dt = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
Write-Host "[DEBUG] Timestamp: $dt"

$buildMd = "$env:SCRIPT_PATH\BUILD.md"
Add-Content $buildMd "Build mode: $Mode"
Add-Content $buildMd "Date: $dt"
Get-ChildItem "$env:SCRIPT_PATH\$env:vietstar" -Filter *.iso | ForEach-Object {
    Add-Content $buildMd "Built file: $($_.Name)"
}
Add-Content $buildMd ""

$remote = "$($env:RCLONE_PATH)$($env:vietstar)/$folder"
Write-Host "[UPLOAD] To $remote"
& $env:SCRIPT_PATH\rclone.exe copy "$env:SCRIPT_PATH\$env:vietstar" "$remote" --include "*.iso"
if ($LASTEXITCODE -ne 0) {
    Write-Error "[ERROR] Upload failed (rclone copy errorlevel=$LASTEXITCODE)"
    exit 1
}

Write-Host "[CLEANUP] Deleting local ISO"
Remove-Item "$env:SCRIPT_PATH\$env:vietstar\*.iso" -Force -ErrorAction SilentlyContinue

Write-Host "[UPLOAD] Done"
