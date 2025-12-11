param(
    [Parameter(Mandatory=$true)][string]$SourceUrl,
    [Parameter(Mandatory=$true)][string]$PipePath
)

$ErrorActionPreference = 'Stop'

function Process-DownloaderOutput {
    param([string]$SourceUrl,[string]$PipePath)

    try {
        $dlOutput  = (& php (Join-Path $env:REPO_PATH "downloader.php") $SourceUrl 2>&1 | Out-String)
    } catch {
		Write-Error ("PHP downloader failed for " + $SourceUrl + ": " + $_.Exception.Message)
        throw
    }

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

            # Gọi rules.ps1 để phân loại folder
            $folder = & (Join-Path $env:REPO_PATH "scripts\rules.ps1") -FileNameA $filenameA
            if (-not $folder) { Write-Host "WARN: skip file due to no matching rule"; continue }

            # Gọi check-exists.ps1 để lấy JSON status
            $RawJson = (& (Join-Path $env:REPO_PATH "scripts\check-exists.ps1") -Mode "auto" -FileNameA $filenameA -Folder $folder 2>&1 | Out-String).Trim()
            Write-Host "DEBUG: check-exists raw=[$RawJson]"
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

# Thực thi: log chi tiết rồi ném lại lỗi để YAML nhận đúng exit code
try {
    Process-DownloaderOutput -SourceUrl $SourceUrl -PipePath $PipePath
} catch {
    Write-Error "downloader.ps1 failed for $SourceUrl"
    if ($_.ScriptStackTrace) { Write-Host "ERROR stack: $($_.ScriptStackTrace)" }
    throw
}
