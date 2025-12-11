param(
    [Parameter(Mandatory=$true)][string]$SourceUrl,
    [Parameter(Mandatory=$true)][string]$PipePath
)

$ErrorActionPreference = 'Stop'

function Process-DownloaderOutput {
    param([string]$SourceUrl,[string]$PipePath)

    # --- Gọi PHP ---
    $dlOutput = (& php (Join-Path $env:REPO_PATH "downloader.php") $SourceUrl 2>&1 | Out-String)
    $phpExit = $LASTEXITCODE

    # Ghi vào debug.log
    $debugPath = Join-Path $env:SCRIPT_PATH "debug.log"
    Add-Content -Path $debugPath -Value "=== downloader.php output for $SourceUrl ==="
    Add-Content -Path $debugPath -Value $dlOutput
    Add-Content -Path $debugPath -Value "=== PHP exit code: $phpExit ==="

    if ($phpExit -ne 0) {
        $errPath = Join-Path $env:SCRIPT_PATH "errors.log"
        $msg = "ERROR: PHP exit code $phpExit for $SourceUrl"
        Write-Error $msg
        Add-Content -Path $errPath -Value $msg
        $dlOutput -split "`r?`n" | ForEach-Object {
            if ($_ -and $_.Trim().Length -gt 0) { Add-Content -Path $errPath -Value "  >> $_" }
        }
        exit $phpExit
    }

    # --- Xử lý output ---
    $realLines = ($dlOutput -replace "`r`n","`n" -replace "`r","`n").Trim() -split "`n"
    Write-Host "DEBUG: downloader lines count=[$($realLines.Count)]"

    foreach ($rl in $realLines) {
        try {
            $rl = $rl.Trim()
            if ([string]::IsNullOrWhiteSpace($rl)) { continue }
            if (-not ($rl -match '^https?://')) { Write-Host "WARN: skip non-http line"; continue }

            Write-Host "DEBUG: downloader line=[$rl]"
            $filenameA = [System.IO.Path]::GetFileName($rl)
            if ([string]::IsNullOrWhiteSpace($filenameA)) { Write-Host "WARN: empty filenameA"; continue }

            # --- Gọi rules.ps1 ---
            $folder = & (Join-Path $env:REPO_PATH "scripts\rules.ps1") -FileNameA $filenameA
            $rulesExit = $LASTEXITCODE
            Write-Host "DEBUG: rules.ps1 exit code = $rulesExit"
            if (-not $folder) { Write-Host "WARN: skip file due to no matching rule"; continue }

            # --- Gọi check-exists.ps1 ---
            $RawJson = (& (Join-Path $env:REPO_PATH "scripts\check-exists.ps1") -Mode "auto" -FileNameA $filenameA -Folder $folder 2>&1 | Out-String).Trim()
            $checkExit = $LASTEXITCODE
            Write-Host "DEBUG: check-exists.ps1 exit code = $checkExit"
            Write-Host "DEBUG: check-exists raw=[$RawJson]"

            # Nếu check-exists trả về 3 → coi là trạng thái upload, không fail
            if ($checkExit -eq 3) {
                Write-Host "INFO: check-exists signaled upload for $filenameA"
                $global:LASTEXITCODE = 0   # reset để không propagate ra ngoài
            }

            if (-not ($RawJson.StartsWith("{"))) { throw "check-exists returned non-JSON for file [$filenameA]" }

            $Info = $RawJson | ConvertFrom-Json
            Write-Host "DEBUG: Parsed → status=[$($Info.status)], key_date=[$($Info.key_date)], filenameB=[$($Info.filenameB)], folder=[$($Info.folder)], delete=[$($Info.filenameB_delete)]"

            $pipeLine = "$($Info.status)|$rl|$folder|$filenameA|$($Info.filenameB)|$($Info.key_date)|$($Info.filenameB_delete)"
            Add-Content $PipePath $pipeLine
            Write-Host "DEBUG: Write pipe=[$pipeLine]"
        } catch {
            Write-Error "Process line failed for [$rl]: $($_.Exception.Message)"
            throw
        }
    }
}

# --- Thực thi ---
try {
    Process-DownloaderOutput -SourceUrl $SourceUrl -PipePath $PipePath
} catch {
    Write-Error "downloader.ps1 failed for $SourceUrl"
    if ($_.ScriptStackTrace) { Write-Host "ERROR stack: $($_.ScriptStackTrace)" }
    throw
}
