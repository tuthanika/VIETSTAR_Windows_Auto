param(
    [string]$Mode,
    [hashtable]$Input
)

Write-Host "=== Build start for $Mode ==="
Write-Host "[DEBUG] Input keys=$($Input.Keys -join ', ')"
Write-Host "[DEBUG] Env for CMD:"
Write-Host "  vietstar=$env:vietstar"
Write-Host "  silent=$env:silent"
Write-Host "  oem=$env:oem"
Write-Host "  dll=$env:dll"
Write-Host "  driver=$env:driver"
Write-Host "  iso=$env:iso"
Write-Host "  boot7=$env:boot7"

# Build must call file.cmd mode (exactly as required)
$cmdFile = "$env:SCRIPT_PATH\zzz.Windows-imdisk.cmd"
if (-not (Test-Path $cmdFile)) {
    Write-Error "[ERROR] Build script not found: $cmdFile"
    exit 1
}

Write-Host "[DEBUG] Calling: zzz.Windows-imdisk.cmd $Mode"
cmd /c `"\"$cmdFile\" $Mode`"
$exitCode = $LASTEXITCODE
Write-Host "[DEBUG] zzz.Windows-imdisk.cmd exit code=$exitCode"
if ($exitCode -ne 0) {
    Write-Warning "[WARN] zzz.Windows-imdisk.cmd returned non-zero exit code ($exitCode)"
}

# Define build output folder per mode (adjust to your cmd behavior)
$buildOut = "$env:SCRIPT_PATH\output\$Mode"
Write-Host "[DEBUG] Expected build output: $buildOut"

Write-Output @{
    Mode = $Mode
    BuildPath = $buildOut
    ExitCode = $exitCode
}
