foreach ($line in $lines) {
  Write-Host "DEBUG: uploader line=[$line]"
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
  Write-Host "DEBUG: remoteDir=[$remoteDir], oldDir=[$oldDir]"

  if ($status -eq 'exists') {
    Write-Host "Skip: $filenameA already exists in $folder"
    continue
  }
  elseif ($status -eq 'upload') {
    if (-not $realLink -or -not ($realLink -match '^https?://')) {
      Write-Host "WARN: realLink invalid, skip [$realLink]"
      continue
    }

    Write-Host "DEBUG: Start download $filenameA"
    $opts = $env:ARIA2_OPTS -split '\s+'
    & "$env:SCRIPT_PATH\aria2c.exe" --dir="$env:DOWNLOAD_DIR" --out="$filenameA" @opts $realLink
    Write-Host "DEBUG: aria2c exit=$LASTEXITCODE"
    if ($LASTEXITCODE -ne 0) { Write-Error "Download failed: $filenameA"; exit 1 }

    $localFile = "$env:DOWNLOAD_DIR\$filenameA"
    if (-not (Test-Path $localFile)) { Write-Error "File not found after download: $filenameA"; exit 1 }

    # Tạo thư mục old nếu chưa có
    & "$env:SCRIPT_PATH\rclone.exe" mkdir "$oldDir" --config "$env:RCLONE_CONFIG_PATH" | Out-Null

    # Xử lý deleteList: move hoặc delete file cũ
    if ($deleteList) {
      foreach ($del in $deleteList -split '\|') {
        if ([string]::IsNullOrWhiteSpace($del)) { continue }
        Write-Host "DEBUG: Moving old file to oldDir: $del"
        & "$env:SCRIPT_PATH\rclone.exe" move "$remoteDir/$del" "$oldDir" --config "$env:RCLONE_CONFIG_PATH" --ignore-existing
      }
    }

    # Upload file mới
    $flags = $env:RCLONE_FLAG -split '\s+'
    Write-Host "DEBUG: Uploading $filenameA to $remoteDir"
    & "$env:SCRIPT_PATH\rclone.exe" copy "$(Resolve-Path $localFile)" "$remoteDir" --config "$env:RCLONE_CONFIG_PATH" @flags --progress
    Write-Host "DEBUG: rclone copy exit=$LASTEXITCODE"
    if ($LASTEXITCODE -ne 0) { Write-Error "Upload failed: $filenameA"; exit 1 }

    # Xoá file tạm
    Remove-Item "$localFile" -Force
    Write-Host "Done: $filenameA"
  }
}
