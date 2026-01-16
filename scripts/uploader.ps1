param(
    [string]$PipePath = (Join-Path $env:SCRIPT_PATH "links.final.txt")
)

$ErrorActionPreference = 'Stop'

$lines = Get-Content $PipePath -ErrorAction SilentlyContinue
Write-Host "DEBUG: links.final.txt count=$($lines.Count)"
if (-not $lines -or $lines.Count -eq 0) { Write-Host "No new links. Done."; exit 0 }

foreach ($line in $lines) {
  Write-Host "DEBUG: uploader line=[$line]"
  $parts = $line -split '\|'
  if ($parts.Count -lt 7) { Write-Host "WARN: bad line format, skip"; continue }

  $status     = $parts[0]
  $realLink   = $parts[1]
  $folder     = $parts[2]
  $filenameA  = $parts[3]
  $filenameB  = $parts[4]
  $key_date   = $parts[5]
  $deleteList = $parts[6]

  Write-Host "DEBUG: Parsed → status=[$status], folder=[$folder], filenameA=[$filenameA], filenameB=[$filenameB], key_date=[$key_date], deleteList=[$deleteList]"

  $remoteDir = "${env:REMOTE_NAME}:${env:REMOTE_TARGET}/$folder"
  $oldDir    = "$remoteDir/old"

  # Flags cho rclone
  $flags = $env:rclone_flag -split '\s+'

  if ($status -eq 'exists') {
    Write-Host "Skip: $filenameA already exists"; continue
  }
  elseif ($status -eq 'upload') {
    if (-not $realLink -or -not ($realLink -match '^https?://')) { Write-Host "WARN: realLink invalid"; continue }

    # Đảm bảo tạo thư mục old trước
    & "$env:SCRIPT_PATH\rclone.exe" mkdir "$oldDir" --config "$env:RCLONE_CONFIG_PATH" | Out-Null

    # Move file B từ main → old
    if (-not [string]::IsNullOrWhiteSpace($filenameB)) {
      Write-Host "DEBUG: Move B to old → $filenameB"
      & "$env:SCRIPT_PATH\rclone.exe" move "$remoteDir/$filenameB" "$oldDir" --config "$env:RCLONE_CONFIG_PATH" --ignore-existing
    }

    # Xóa các bản thừa trong old
    if (-not [string]::IsNullOrWhiteSpace($deleteList)) {
      foreach ($del in $deleteList -split '\|') {
        if ([string]::IsNullOrWhiteSpace($del)) { continue }
        Write-Host "DEBUG: Delete old → $del"
        & "$env:SCRIPT_PATH\rclone.exe" deletefile "$oldDir/$del" --config "$env:RCLONE_CONFIG_PATH" @flags
      }
    }

    # Download bản mới
    Write-Host "DEBUG: Start download $filenameA"
    $opts = $env:ARIA2_OPTS -split '\s+'
    & "$env:SCRIPT_PATH\aria2c.exe" --dir="$env:DOWNLOAD_DIR" --out="$filenameA" @opts $realLink
    if ($LASTEXITCODE -ne 0) { Write-Error "Download failed: $filenameA"; exit 1 }

    $localFile = "$env:DOWNLOAD_DIR\$filenameA"
    if (-not (Test-Path $localFile)) { Write-Error "File not found after download: $filenameA"; exit 1 }

    # Upload bản mới vào main
    Write-Host "DEBUG: Uploading $filenameA → $remoteDir"
    & "$env:SCRIPT_PATH\rclone.exe" copy "$(Resolve-Path $localFile)" "$remoteDir" --config "$env:RCLONE_CONFIG_PATH" @flags --progress
    if ($LASTEXITCODE -ne 0) { Write-Error "Upload failed: $filenameA"; exit 1 }

    # Xóa file tạm
    Remove-Item "$localFile" -Force
    Write-Host "Done: $filenameA"
  }
  else {
    Write-Host "WARN: unsupported status [$status]"
  }
}
