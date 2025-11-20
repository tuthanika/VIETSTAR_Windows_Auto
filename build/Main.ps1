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
    # Thư mục chứa ISO silent
    $isoFolder = Join-Path $env:SCRIPT_PATH "z.Silent"
    
    # Lấy file ISO mới nhất trong thư mục
    $isoSilent = Get-ChildItem -Path $isoFolder -Filter *.iso -File |
                 Sort-Object LastWriteTime -Descending |
                 Select-Object -First 1

    if ($isoSilent) {
        Write-Host "[DEBUG] Mounting Silent ISO: $($isoSilent.FullName) to drive A:"
        & imdisk -a -m A: -f $isoSilent.FullName
    } else {
        Write-Warning "[WARN] No ISO file found in $isoFolder"
    }

    # Override silent path to A:\
    $env:silent = "A:\Apps\exe"
    Write-Host "[DEBUG] Silent ISO mounted, silent path set to $env:silent"

    # Set env paths for CMD (absolute) before calling build
    $env:vietstar = Join-Path $env:SCRIPT_PATH $env:vietstar_path
    $env:silent   = $env:silent   # giữ nguyên vì đã mount A:\
    $env:oem      = Join-Path $env:SCRIPT_PATH $env:oem_path
    $env:dll      = Join-Path $env:SCRIPT_PATH $env:dll_path
    $env:driver   = Join-Path $env:SCRIPT_PATH $env:driver_path
    $env:iso      = Join-Path $env:SCRIPT_PATH $env:iso_path
    $env:boot7    = Join-Path $env:SCRIPT_PATH $env:boot7_path

    Write-Host "[DEBUG] Env paths set:"
    Write-Host "  vietstar=$env:vietstar"
    Write-Host "  silent=$env:silent"
    Write-Host "  oem=$env:oem"
    Write-Host "  dll=$env:dll"
    Write-Host "  driver=$env:driver"
    Write-Host "  iso=$env:iso"
    Write-Host "  boot7=$env:boot7"

    # Call build (build sẽ ghi JSON)
    $null = . "$env:SCRIPT_PATH\build\Build.ps1" -Mode $m -Input $prepResult

    # Đọc JSON (Raw để lấy toàn chuỗi)
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

    # Chỉ gọi Upload nếu ISO ready
    if ($buildResult.Status -eq "ISO ready") {
        Write-Host "[DEBUG] Calling Upload for mode $m (Upload sẽ tự xác định remote path theo env rules)"
		& "$env:SCRIPT_PATH\build\Upload.ps1" -Mode $m
    } else {
        Write-Host "[DEBUG] Skip Upload for mode $m (Status=$($buildResult.Status))"
    }

    Write-Host "=== MODE DONE: $m ==="
}

Write-Host "=== MAIN PIPELINE FINISHED ==="
