$pipePath = (Join-Path $env:SCRIPT_PATH "links.final.txt")
$lines = Get-Content $pipePath -ErrorAction SilentlyContinue
if (-not $lines -or $lines.Count -eq 0) { Write-Host "No new links. Done."; exit 0 }

foreach ($line in $lines) {
  if ([string]::IsNullOrWhiteSpace($line)) { continue }
  $parts = $line -split '\|'
  $status     = $parts[0]
  $realLink   = $parts[1]
  $folder     = $parts[2]
  $filenameA  = $parts[3]
  $baseKey    = $parts[4]
  $dateTag    = $parts[5]
  $deleteList = $parts[6]

  $remoteDir = "${env:REMOTE_NAME}:${env:REMOTE_TARGET}/$folder"
  $oldDir    = "$remoteDir/old"

  if ($status -eq 'exists') {
    Write-Host "Skip: $filenameA already exists in $folder"
    continue
  }
  elseif ($status -eq 'upload') {
    $opts = $env:ARIA2_OPTS -split '\s+'
    & "$env:SCRIPT_PATH\aria2c.exe" --dir="$env:DOWNLOAD_DIR" --out="$filenameA" @opts $realLink
    if ($LASTEXITCODE -ne 0) { Write-Error "Download failed: $filenameA"; exit 1 }

    $localFile = "$env:DOWNLOAD_DIR\$filenameA"
    if (-not (Test-Path $localFile)) { Write-Error "File not found after download: $filenameA"; exit 1 }

    & "$env:SCRIPT_PATH\rclone.exe" mkdir "$oldDir" --config "$env:RCLONE_CONFIG_PATH" | Out-Null

    if ($deleteList) {
      foreach ($del in $deleteList -split '\|') {
        if ([string]::IsNullOrWhiteSpace($del)) { continue }
        Write-Host "Deleting old file: $del"
        & "$env:SCRIPT_PATH\rclone.exe" deletefile "$oldDir/$del" --config "$env:RCLONE_CONFIG_PATH"
      }
    }

    $flags = $env:RCLONE_FLAG -split '\s+'
    & "$env:SCRIPT_PATH\rclone.exe" copy "$(Resolve-Path $localFile)" "$remoteDir" --config "$env:RCLONE_CONFIG_PATH" @flags --progress
    if ($LASTEXITCODE -ne 0) { Write-Error "Upload failed: $filenameA"; exit 1 }

    Remove-Item "$localFile" -Force
    Write-Host "Done: $filenameA"
  }
}
