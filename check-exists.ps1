param([string]$FileNameA,[string]$Folder)

Write-Host "DEBUG: check-exists start → FileNameA=[$FileNameA], Folder=[$Folder]"

$remoteDir = "${env:REMOTE_NAME}:${env:REMOTE_TARGET}/$Folder"
Write-Host "DEBUG: remoteDir=[$remoteDir]"

$filesMain = @()
$r = & "$env:SCRIPT_PATH\rclone.exe" lsjson "$remoteDir" --config "$env:RCLONE_CONFIG_PATH" 2>$null
Write-Host "DEBUG: rclone lsjson exit=$LASTEXITCODE, raw=[$r]"

if ($LASTEXITCODE -eq 0 -and $r) {
  try { $filesMain = $r | ConvertFrom-Json } catch { $filesMain = @() }
}
Write-Host "DEBUG: filesMain count=$($filesMain.Count)"

# Parse baseKey/dateTag
$baseKey = $FileNameA
$dateTag = ""
if ($FileNameA -match "(.+)_v(\d{2}\.\d{2}\.\d{2})") {
  $baseKey = $matches[1]
  $dateTag = "v$($matches[2])"
}
Write-Host "DEBUG: baseKey=[$baseKey], dateTag=[$dateTag]"

$related = $filesMain | Where-Object { $_.Name -like "$baseKey*" }
Write-Host "DEBUG: related count=$($related.Count)"

$exactExists = $related | Where-Object { $_.Name -eq $FileNameA } | Select-Object -First 1
if ($exactExists) {
  Write-Host "DEBUG: exactExists found"
  [pscustomobject]@{
    status     = "exists"
    filenameA  = $FileNameA
    folder     = $Folder
    baseKey    = $baseKey
    dateTag    = $dateTag
    deleteList = ""
  } | ConvertTo-Json -Compress
  return
}

# Rotation
$deleteList = ""
$max = [int]([Environment]::GetEnvironmentVariable("MAX_FILE"))
if ($max -lt 1) { $max = 1 }
if ($related.Count -gt $max) {
  $sorted   = $related | Sort-Object ModTime -Descending
  $toDelete = if ($sorted.Count -gt $max) { $sorted[$max..($sorted.Count-1)] } else { @() }
  $deleteList = ($toDelete | ForEach-Object { $_.Name }) -join "|"
}
Write-Host "DEBUG: deleteList=[$deleteList]"

[pscustomobject]@{
  status     = "upload"
  filenameA  = $FileNameA
  folder     = $Folder
  baseKey    = $baseKey
  dateTag    = $dateTag
  deleteList = $deleteList
} | ConvertTo-Json -Compress
