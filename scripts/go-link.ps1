param(
    [Parameter(Mandatory=$true)][string]$ThreadUrl
)

$ErrorActionPreference = 'Stop'

# ENV
$ua = [Environment]::GetEnvironmentVariable("FORUM_UA")
if ([string]::IsNullOrWhiteSpace($ua)) {
  $ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
}
$cookieHeader = [Environment]::GetEnvironmentVariable("FORUM_COOKIE")
if ([string]::IsNullOrWhiteSpace($cookieHeader)) {
  Write-Host "ERROR: FORUM_COOKIE env empty"
  exit 1
}

# Tải HTML thread
$page = Invoke-WebRequest $ThreadUrl -Headers @{ Cookie = $cookieHeader } -UserAgent $ua
if ($page.Content -notmatch "tuthanika") {
  Write-Host "WARN: Login failed"
  Write-Output ""
  exit 1
}

# Regex tìm go-link
$goMatches = [regex]::Matches($page.Content,'https://go\.rg-adguard\.net/[^\s"<>]+')
Write-Host "DEBUG: goLinks found=$($goMatches.Count)"

if ($goMatches.Count -lt 1) {
  Write-Host "WARN: No goLink found"
  Write-Output ""
  exit 0
}

# Output: go-link đầu tiên
Write-Output $goMatches[0].Value
