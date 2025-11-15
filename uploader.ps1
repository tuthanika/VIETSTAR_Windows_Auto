$lines = Get-Content "$env:SCRIPT_PATH\links.final.txt" -ErrorAction SilentlyContinue
if (-not $lines -or $lines.Count -eq 0) {
  Write-Host "No new links. Done."
  exit 0
}

foreach ($line in $lines) {
  $parts = $line -split '\|'
  $status    = $parts[0]
  $realLink  = $parts[1]
  $folder    = $parts[2]
  $filenameA = $parts[3]

  if ($status -eq "exists") {
    Write-Host "Skip: $filenameA already exists in $folder"
    continue
  }
  elseif ($status -eq "upload") {
    Write-Host "Uploading $filenameA to $folder"
    $remoteDir = "${env:REMOTE_NAME}:${env:REMOTE_TARGET}/$folder"

    & "$env:SCRIPT_PATH\aria2c.exe" --dir="$env:DOWNLOAD_DIR" --out="$filenameA" $realLink
    if ($LASTEXITCODE -ne 0) { Write-Error "Download failed for $filenameA"; exit 1 }

    $localFile = "$env:DOWNLOAD_DIR\$filenameA"
    & "$env:SCRIPT_PATH\rclone.exe" copy "$(Resolve-Path $localFile)" "$remoteDir" --config "$env:RCLONE_CONFIG_PATH" --progress
    if ($LASTEXITCODE -ne 0) { Write-Error "Upload failed for $filenameA"; exit 1 }

    Remove-Item "$localFile" -Force
    Write-Host "Uploaded and cleaned: $filenameA"
  }
}
