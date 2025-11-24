param([string]$Mode)

Write-Host "=== MAIN PIPELINE START ==="
Write-Host "[DEBUG] Mode input=$Mode"

if ([string]::IsNullOrWhiteSpace($env:FILE_CODE_RULES)) {
    Write-Error "[ERROR] FILE_CODE_RULES not found in env"
    exit 1
}

$rules = $env:FILE_CODE_RULES | ConvertFrom-Json
Write-Host "[DEBUG] Rules count=$($rules.Count)"

# Determine modes to run
$runModes = if ($Mode -eq "all") { @($rules.Mode) } else { @($Mode) }
Write-Host "[DEBUG] Will run modes: $($runModes -join ', ')"

function Write-RuleEnvForMode {
    param([object]$r)

    $kv = @(
        "mode=$($r.Mode)",
        "folder=$($r.Folder)",
        "patterns=$([string]::Join(';',$r.Patterns))"
    )
    if ($r.DriverFolder)   { $kv += "drvFolder=$($r.DriverFolder)" }
    if ($r.DriverPatterns) { $kv += "drvPatterns=$([string]::Join(';',$r.DriverPatterns))" }
    if ($r.BootFolder)     { $kv += "bootFolder=$($r.BootFolder)" }
    if ($r.BootPatterns)   { $kv += "bootPatterns=$([string]::Join(';',$r.BootPatterns))" }
    if ($r.SilentFolder)   { $kv += "silentFolder=$($r.SilentFolder)" }
    if ($r.SilentPatterns) { $kv += "silentPatterns=$([string]::Join(';',$r.SilentPatterns))" }
    if ($r.isoFolder)      { $kv += "isoFolder=$($r.isoFolder)" }
    if ($r.VietstarFolder) { $kv += "vietstarFolder=$($r.VietstarFolder)" }

    $outPath = "$env:SCRIPT_PATH\rule.env"
    Set-Content -Path $outPath -Value ($kv -join "`n")
    Write-Host "[DEBUG] Wrote rule.env for mode=$($r.Mode) at $outPath"
    Get-Content $outPath | ForEach-Object { Write-Host "  $_" }
}

foreach ($m in $runModes) {
    Write-Host "=== RUN MODE: $m ==="
    $r = $rules | Where-Object { $_.Mode -eq $m }
    if (-not $r) {
        Write-Warning "[WARN] Mode '$m' not found in FILE_CODE_RULES, skipping"
        continue
    }

    Write-RuleEnvForMode -r $r

    # Prepare
    $prepOut = @(& "$env:SCRIPT_PATH\build\Prepare.ps1" -Mode $m)
    $prepResult = $prepOut | Where-Object { $_ -is [hashtable] } | Select-Object -Last 1
    if (-not $prepResult) { $prepResult = @{} }

    # Lấy rule theo mode hiện tại ($m)
    $rule = $rules | Where-Object { $_.Mode -eq $m } | Select-Object -First 1
    if ($rule) {
        $vsFolder     = if ($rule.VietstarFolder) { $rule.VietstarFolder } else { $rule.Folder }
        $isoFolder    = if ($rule.isoFolder)      { $rule.isoFolder }      else { $rule.Folder }
        $drvFolder    = if ($rule.DriverFolder)   { $rule.DriverFolder }   else { "" }
        $silentFolder = if ($rule.SilentFolder)   { $rule.SilentFolder }   else { "" }

        $env:vietstar = Join-Path (Join-Path $env:SCRIPT_PATH $env:vietstar_path) $vsFolder
        $env:iso      = Join-Path (Join-Path $env:SCRIPT_PATH $env:iso_path)      $isoFolder
        $env:driver   = if ([string]::IsNullOrWhiteSpace($drvFolder)) {
                            Join-Path $env:SCRIPT_PATH $env:driver_path
                        } else {
                            Join-Path (Join-Path $env:SCRIPT_PATH $env:driver_path) $drvFolder
                        }
        $env:silent   = if ([string]::IsNullOrWhiteSpace($silentFolder)) {
                            Join-Path $env:SCRIPT_PATH $env:silent_path
                        } else {
                            Join-Path (Join-Path $env:SCRIPT_PATH $env:silent_path) $silentFolder
                        }
    }

    # Mount Silent ISO to A:
    $isoSilent = Get-ChildItem -Path $env:silent -Filter *.iso -File |
                 Sort-Object LastWriteTime -Descending |
                 Select-Object -First 1

    if ($isoSilent) {
        Write-Host "[DEBUG] Mounting Silent ISO: $($isoSilent.FullName) to drive A:"
        & imdisk -a -m A: -f $isoSilent.FullName
        $env:silent = "A:\Apps\exe"
        Write-Host "[DEBUG] Silent ISO mounted, silent path set to $env:silent"
    } else {
        Write-Warning "[WARN] No ISO file found in $env:silent"
    }

    # Set env paths for CMD (absolute) before calling build
    $env:oem   = Join-Path $env:SCRIPT_PATH $env:oem_path
    $env:dll   = Join-Path $env:SCRIPT_PATH $env:dll_path
    $env:boot7 = Join-Path $env:SCRIPT_PATH $env:boot7_path

    Write-Host "[DEBUG] Env paths set:"
    Write-Host "  silent=$env:silent"
    Write-Host "  oem=$env:oem"
    Write-Host "  dll=$env:dll"
    Write-Host "  driver=$env:driver"
    Write-Host "  boot7=$env:boot7"
    Write-Host "  iso=$env:iso"
    Write-Host "  vietstar=$env:vietstar"

    # Call build
    $null = . "$env:SCRIPT_PATH\build\Build.ps1" -Mode $m -Input $prepResult

    # Đọc JSON
    $outFile = Join-Path $env:SCRIPT_PATH "build_result_$m.json"
    if (-not (Test-Path $outFile)) {
        Write-Warning "[WARN] Build result file not found for mode $m"
        continue
    }

    $json = Get-Content $outFile -Raw
    $buildResult = $json | ConvertFrom-Json
    if (-not $buildResult) {
        Write-Warning "[WARN] Failed to parse build result JSON for mode $m"
        continue
    }

    Write-Host "[DEBUG] Build result: Status=$($buildResult.Status), BuildPath=$($buildResult.BuildPath)"

    if ($buildResult.Status -eq "ISO ready") {
        Write-Host "[DEBUG] Calling Upload for mode $m"
        & "$env:SCRIPT_PATH\build\Upload.ps1" -Mode $m
    } else {
        Write-Host "[DEBUG] Skip Upload for mode $m (Status=$($buildResult.Status))"
    }

    Write-Host "=== MODE DONE: $m ==="
}

Write-Host "=== MAIN PIPELINE FINISHED ==="
