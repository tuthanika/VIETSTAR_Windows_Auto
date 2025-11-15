param(
  [string]$FileNameA,
  [string]$Folder
)

$remoteRoot = "${env:REMOTE_NAME}:${env:REMOTE_TARGET}"
$remoteDir  = "$remoteRoot/$Folder"

# Kiểm tra tồn tại thư mục
$dirExists = $false
& "$env:SCRIPT_PATH\rclone.exe" lsd "$remoteDir" --config "$env:RCLONE_CONFIG_PATH" 2>$null
if ($LASTEXITCODE -eq 0) { $dirExists = $true } else { $global:LASTEXITCODE = 0 }

$filesMain = @()
if ($dirExists) {
  $jsonMain = & "$env:SCRIPT_PATH\rclone.exe" lsjson "$remoteDir" --config "$env:RCLONE_CONFIG_PATH" 2>$null
  if ($LASTEXITCODE -ne 0) { $global:LASTEXITCODE = 0 }
  if ($jsonMain -and $jsonMain.Trim().Length -gt 0) {
    try { $filesMain = $jsonMain | ConvertFrom-Json } catch {}
  }
}

# Kiểm tra tuyệt đối
$exactExists = $filesMain | Where-Object { $_.Name -eq $FileNameA } | Select-Object -First 1
if ($exactExists) {
    [pscustomobject]@{ status="exists"; filenameA=$FileNameA; folder=$Folder; baseKey=""; dateTag=""; deleteList="" } | ConvertTo-Json -Compress
    return
}

# Nếu không khớp → upload
[pscustomobject]@{
    status     = "upload"
    filenameA  = $FileNameA
    folder     = $Folder
    baseKey    = ""   # có thể parse thêm nếu cần
    dateTag    = ""   # có thể parse thêm nếu cần
    deleteList = ""   # có thể tính toán thêm nếu cần
} | ConvertTo-Json -Compress
