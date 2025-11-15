param(
  [string]$FileNameA,
  [string]$Folder
)

$remoteDir = "${env:REMOTE_NAME}:${env:REMOTE_TARGET}/$Folder"
$filesMain = @()

$r = & "$env:SCRIPT_PATH\rclone.exe" lsjson "$remoteDir" --config "$env:RCLONE_CONFIG_PATH" 2>$null
if ($LASTEXITCODE -eq 0 -and $r) {
  try { $filesMain = $r | ConvertFrom-Json } catch { $filesMain = @() }
}

$baseKey = $FileNameA
$dateTag = ""
if ($FileNameA -match "(.+)_v(\d{2}\.\d{2}\.\d{2})") {
  $baseKey = $matches[1]
  $dateTag = "v$($matches[2])"
}

$related = $filesMain | Where-Object { $_.Name -like "$baseKey*" }
$exactExists = $related | Where-Object { $_.Name -eq $FileNameA } | Select-Object -First 1
if ($exactExists) {
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

$deleteList = ""
$max = [int]([Environment]::GetEnvironmentVariable("MAX_FILE"))
if ($max -lt 1) { $max = 1 }
if ($related.Count -gt $max) {
  $sorted   = $related | Sort-Object ModTime -Descending
  $toDelete = if ($sorted.Count -gt $max) { $sorted[$max..($sorted.Count-1)] } else { @() }
  $deleteList = ($toDelete | ForEach-Object { $_.Name }) -join "|"
}

[pscustomobject]@{
  status     = "upload"
  filenameA  = $FileNameA
  folder     = $Folder
  baseKey    = $baseKey
  dateTag    = $dateTag
  deleteList = $deleteList
} | ConvertTo-Json -Compress
