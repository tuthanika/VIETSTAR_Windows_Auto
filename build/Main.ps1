param([string]$Mode)

Write-Host "=== MAIN PIPELINE START ==="
Write-Host "[DEBUG] Mode input=$Mode"
Write-Host "[DEBUG] SCRIPT_PATH=$env:SCRIPT_PATH"

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

    # Mount Silent ISO to A:
    $isoSilent = "$env:SCRIPT_PATH\z.Silent.iso"
    Write-Host "[DEBUG] Mounting Silent ISO: $isoSilent to drive A:"
    & imdisk -a -m A: -f "$isoSilent"

    # Override silent path to A:\
    $env:silent = "A:\Apps\exe"
    Write-Host "[DEBUG] Silent ISO mounted, silent path set to $env:silent"

    # Set env paths for CMD (absolute) before calling build
    $env:vietstar = "$env:SCRIPT_PATH\$env:vietstar"
    $env:silent   = "$env:silent"   # đã mount A:\ ở trên
    $env:oem      = "$env:SCRIPT_PATH\$env:oem"
    $env:dll      = "$env:SCRIPT_PATH\$env:dll"
    $env:driver   = "$env:SCRIPT_PATH\$env:driver"
    $env:iso      = "$env:SCRIPT_PATH\$env:iso"
    $env:boot7    = "$env:SCRIPT_PATH\$env:boot7"

    Write-Host "[DEBUG] Env paths set:"
    Write-Host "  vietstar=$env:vietstar"
    Write-Host "  silent=$env:silent"
    Write-Host "  oem=$env:oem"
    Write-Host "  dll=$env:dll"
    Write-Host "  driver=$env:driver"
    Write-Host "  iso=$env:iso"
    Write-Host "  boot7=$env:boot7"

    # Call build
    $buildOut = . "$env:SCRIPT_PATH\build\Build.ps1" -Mode $m -Input $prepResult

    Write-Host "[DEBUG] Raw buildOut type=$($buildOut.GetType().FullName)"
    Write-Host "[DEBUG] Raw buildOut value=$buildOut"

    $buildResult = $buildOut
    if ($buildOut -isnot [hashtable]) {
        $buildResult = $buildOut | Where-Object { $_ -is [hashtable] } | Select-Object -Last 1
    }

    Write-Host "[DEBUG] buildResult type=$($buildResult.GetType().FullName)"
    Write-Host "[DEBUG] buildResult keys=$($buildResult.Keys -join ', ')"
    Write-Host "[DEBUG] buildResult.Status=$($buildResult.Status)"
	
    # Call upload (Upload.ps1 đã chấp nhận object, tự chuẩn hóa)
	Write-Host "[DEBUG] Passing to Upload: type=$($buildResult.GetType().FullName)"
	$uploadOut = . "$env:SCRIPT_PATH\build\Upload.ps1" -Mode $m -Input ([hashtable]$buildResult)
    Write-Host "[DEBUG] Called Upload with Input type=$($buildResult.GetType().FullName)"

    # (Optional) Lọc output upload nếu cần hashtable cuối cùng
    $uploadResult = $uploadOut
    if ($uploadOut -isnot [hashtable]) {
        $uploadResult = $uploadOut | Where-Object { $_ -is [hashtable] } | Select-Object -Last 1
    }
    if (-not $uploadResult) {
        Write-Warning "[WARN] Upload returned no result for mode $m"
    }

    Write-Host "=== MODE DONE: $m ==="
}

Write-Host "=== MAIN PIPELINE FINISHED ==="
