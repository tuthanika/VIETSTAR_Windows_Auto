param(
    [Parameter(Mandatory=$true)]
    [string]$TargetFile, 
    
    [Parameter(Mandatory=$true)]
    [string]$Mode
)

$ErrorActionPreference = 'Stop'

# Xác định đường dẫn
$RootPath = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { Get-Location }
$FullFilePath = Join-Path $RootPath $TargetFile
$TempDataFile = Join-Path $RootPath "all_builds_data.txt"

Write-Host "[INFO] Target File: ${FullFilePath}"

if (-not (Test-Path $TempDataFile)) {
    Write-Warning "[WARN] No build data found. Skipping."
    exit 0
}

$allLines = Get-Content $TempDataFile -Encoding utf8
git config user.name "tuthanika-bot"
git config user.email "tuthanika-bot@gmail.com"

# Vòng lặp Retry
for ($i = 1; $i -le 10; $i++) {
    # FIX LỖI TẠI ĐÂY: Dùng ${i} và ${TargetFile}
    Write-Host "--- Attempt ${i}: Syncing ${TargetFile} ---"
    
    Set-Location $RootPath
    git pull origin $env:GITHUB_REF_NAME --rebase

    if (-not (Test-Path $FullFilePath)) {
        $header = @"
# Build History

| Date | Mode | Build# | Time | ISO Gốc | ISO VIETSTAR|
|------|------|--------|------|-----------|------------|
"@
        $header | Out-File $FullFilePath -Encoding utf8
    }

    $content = Get-Content $FullFilePath -Encoding utf8

    foreach ($line in $allLines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split '\|'
        if ($parts.Count -lt 4) { continue }
        
        $B_Date   = $parts[0].Trim()
        $B_Time   = $parts[1].Trim()
        $B_Local  = $parts[2].Trim()
        $B_Remote = $parts[3].Trim()

        $pattern = "\|\s$([regex]::Escape($B_Date))\s\|\s$([regex]::Escape($Mode))\s\|"
        $found = $content | Select-String -Pattern $pattern
        
        $newCounter = 1
        if ($found) {
            $lastRow = $found | Select-Object -Last 1
            $cols = $lastRow.ToString() -split '\|'
            if ($cols.Count -gt 3) {
                $oldVal = 0
                if ([int]::TryParse($cols[3].Trim(), [ref]$oldVal)) {
                    $newCounter = $oldVal + 1
                }
            }
            $newLine = "| $B_Date | $Mode | $newCounter | $B_Time | $B_Local | $B_Remote |"
            $content[$lastRow.LineNumber - 1] = $newLine
        } else {
            $newLine = "| $B_Date | $Mode | 1 | $B_Time | $B_Local | $B_Remote |"
            $content += $newLine
        }
    }

    $content | Set-Content $FullFilePath -Encoding utf8

    git add $TargetFile
    git diff --staged --quiet
    if ($LASTEXITCODE -ne 0) {
        # Fix lỗi biến trong chuỗi commit message luôn cho chắc chắn
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        git commit -m "Lịch sử build VIETSTAR ISO mode ${Mode} (${timestamp})"
        
        git push origin "HEAD:$($env:GITHUB_REF_NAME)"
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[SUCCESS] Updated ${TargetFile}"
            Remove-Item $TempDataFile -ErrorAction SilentlyContinue
            exit 0
        }
    } else {
        Write-Host "[INFO] No changes."
        Remove-Item $TempDataFile -ErrorAction SilentlyContinue
        exit 0
    }

    $wait = Get-Random -Minimum 3 -Maximum 10
    Start-Sleep -Seconds $wait
}

exit 1