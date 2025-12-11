param(
    [Parameter(Mandatory=$true)][string]$SourceUrl,
    [Parameter(Mandatory=$true)][string]$PipePath
)

$ErrorActionPreference = 'Stop'

function Process-DownloaderOutput {
    param([string]$SourceUrl,[string]$PipePath)

    $dlOutput  = (& php (Join-Path $env:REPO_PATH "downloader.php") $SourceUrl | Out-String)
    $realLines = ($dlOutput -replace "`r`n","`n" -replace "`r","`n").Trim() -split "`n"
    Write-Host "DEBUG: downloader lines count=[$($realLines.Count)]"

    foreach ($rl in $realLines) {
        $rl = $rl.Trim()
        if ([string]::IsNullOrWhiteSpace($rl)) { continue }
        if (-not ($rl -match '^https?://')) { Write-Host "WARN: skip non-http line"; continue }

        Write-Host "DEBUG: downloader line=[$rl]"
        $filenameA = [System.IO.Path]::GetFileName($rl)
        if ([string]::IsNullOrWhiteSpace($filenameA)) { Write-Host "WARN: empty filenameA"; continue }

        # Gọi rules.ps1 để phân loại folder
        $folder = & (Join-Path $env:REPO_PATH "scripts\rules.ps1") -FileNameA $filenameA
        if (-not $folder) { Write-Host "WARN: skip file due to no matching rule"; continue }

        # Gọi check-exists.ps1 để lấy JSON status
        $RawJson = (& (Join-Path $env:REPO_PATH "scripts\check-exists.ps1") -Mode "auto" -FileNameA $filenameA -Folder $folder | Out-String).Trim()
        Write-Host "DEBUG: check-exists raw=[$RawJson]"
        if (-not ($RawJson.StartsWith("{"))) { Write-Host "WARN: check-exists no JSON"; continue }

        $Info = $RawJson | ConvertFrom-Json
        Write-Host "DEBUG: Parsed → status=[$($Info.status)], key_date=[$($Info.key_date)], filenameB=[$($Info.filenameB)], folder=[$($Info.folder)], delete=[$($Info.filenameB_delete)]"

        $pipeLine = "$($Info.status)|$rl|$folder|$filenameA|$($Info.filenameB)|$($Info.key_date)|$($Info.filenameB_delete)"
        Add-Content $PipePath $pipeLine
        Write-Host "DEBUG: Write pipe=[$pipeLine]"
    }
}

# Thực thi
try {
    Process-DownloaderOutput -SourceUrl $SourceUrl -PipePath $PipePath
    exit 0
}
catch {
    Write-Host "ERROR: downloader.ps1 failed for $SourceUrl"
    Write-Host "ERROR detail: $($_.Exception.Message)"
    if ($_.ScriptStackTrace) {
        Write-Host "ERROR stack: $($_.ScriptStackTrace)"
    }
    exit 3
}

