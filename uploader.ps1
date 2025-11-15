$pipePath = (Join-Path $env:SCRIPT_PATH "links.final.txt")
$lines = Get-Content $pipePath -ErrorAction SilentlyContinue
Write-Host "DEBUG: links.final.txt count=$($lines.Count)"
if (-not $lines -or $lines.Count -eq 0) { Write-Host "No new links. Done."; exit 0 }

foreach ($line in $lines) {
  Write-Host "DEBUG: uploader line=[$line]"
  $parts = $line -split '\|'
  if ($parts.Count -lt 7) { Write-Host "WARN: bad line format, skip"; continue }

  $status     = $parts[0]
  $realLink   = $parts[1]
  $folder     = $parts[2]
  $filenameA  = $parts[3]   # bản mới sẽ upload
  $filenameB  = $parts[4]   # bản hiện có trong main (sẽ move sang old)
  $key_date   = $parts[5]
  $deleteList = $parts[6]   # danh sách xóa trong old

  Write-Host "DEBUG: Parsed → status=[$status], folder=[$folder], filenameA=[$filenameA], filenameB=[$filenameB], key_date=[$key_date], deleteList=[$deleteList]"

  $remoteDir = "${env:REMOTE_NAME}:${env:REMOTE_TARGET}/$folder"
  $oldDir    = "$remoteDir/old"

  if ($status -eq 'exists') {
    Write-Host "Skip: $filenameA already exists"; continue
  }
  elseif ($status -eq 'upload') {
    if (-not $realLink -or -not ($realLink -match '^https?://')) { Write-Host "WARN: realLink invalid"; continue }

    # Đảm bảo tạo thư mục old trước
    & "$env:SCRIPT_PATH\rclone.exe" mkdir "$oldDir" --config "$env:RCLONE_CONFIG_PATH" | Out-Null

    # 1) Move file B (hiện có) từ main → old
    if (-not [string]::IsNullOrWhiteSpace($filenameB)) {
      Write-Host "DEBUG: Move B to old → $filenameB"
      & "$env:SCRIPT_PATH\rclone.exe" move "$remoteDir/$filenameB" "$oldDir" --config "$env:RCLONE_CONFIG_PATH" --ignore-existing
      Write-Host "DEBUG: rclone move(B) exit=$LASTEXITCODE"
    } else {
      Write-Host "DEBUG: No B in main → skip move"
    }

    # 2) Xóa các bản thừa trong old (deleteList)
    if (-not [string]::IsNullOrWhiteSpace($deleteList)) {
      foreach ($del in $deleteList -split '\|') {
        if ([string]::IsNullOrWhiteSpace($del)) { continue }
        Write-Host "DEBUG: Delete old → $del"
        & "$env:SCRIPT_PATH\rclone.exe" deletefile "$oldDir/$del" --config "$env:RCLONE_CONFIG_PATH"
        Write-Host "DEBUG: rclone deletefile exit=$LASTEXITCODE"
      }
    } else {
      Write-Host "DEBUG: deleteList empty → nothing to delete"
    }

    # 3) Download bản mới
    Write-Host "DEBUG: Start download $filenameA"
    $opts = $env:ARIA2_OPTS -split '\s+'
    & "$env:SCRIPT_PATH\aria2c.exe" --dir="$env:DOWNLOAD_DIR" --out="$filenameA" @opts $realLink
    Write-Host "DEBUG: aria2c exit=$LASTEXITCODE"
    if ($LASTEXITCODE -ne 0) { Write-Error "Download failed: $filenameA"; exit 1 }

    $localFile = "$env:DOWNLOAD_DIR\$filenameA"
    if (-not (Test-Path $localFile)) { Write-Error "File not found after download: $filenameA"; exit 1 }

    # 4) Upload bản mới vào main
    Write-Host "DEBUG: Uploading $filenameA → $remoteDir"
    $flags = $env:RCLONE_FLAG -split '\s+'
    & "$env:SCRIPT_PATH\rclone.exe" copy "$(Resolve-Path $localFile)" "$remoteDir" --config "$env:RCLONE_CONFIG_PATH" @flags --progress
    Write-Host "DEBUG: rclone copy exit=$LASTEXITCODE"
    if ($LASTEXITCODE -ne 0) { Write-Error "Upload failed: $filenameA"; exit 1 }

    # 5) Xóa file tạm
    Remove-Item "$localFile" -Force
    Write-Host "Done: $filenameA"
  }
  else {
    Write-Host "WARN: unsupported status [$status]"
  }
}
