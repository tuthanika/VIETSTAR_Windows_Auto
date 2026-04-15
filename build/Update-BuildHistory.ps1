param(
    [Parameter(Mandatory=$true)]
    [string]$TargetFile
)

$filePath = Join-Path $env:GITHUB_WORKSPACE $TargetFile
$dataFile = Join-Path $env:GITHUB_WORKSPACE "all_builds_data.txt"

# Cấu hình Git bắt buộc
git config --global user.name "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"
git config --global core.autocrlf false

for ($i = 1; $i -le 10; $i++) {
    Write-Host "[RETRY $i/10] Syncing with origin/master..."
    git fetch origin master
    git reset --hard origin/master

    # 1. Tạo file nếu chưa có (Dùng System.IO để đảm bảo encoding chuẩn không lỗi ký tự lạ)
    if (-not (Test-Path $filePath)) {
        $header = "| Date | Mode | Build# | Time | ISO Gốc | ISO VIETSTAR |`n|---|---|---|---|---|---|"
        [System.IO.File]::WriteAllText($filePath, $header + "`r`n", [System.Text.Encoding]::UTF8)
        Write-Host "[DEBUG] Created new $TargetFile"
    }

    # 2. Kiểm tra log build
    if (-not (Test-Path $dataFile)) {
        Write-Host "[INFO] No build data found in $dataFile. Skipping."
        exit 0
    }

    # 3. Đọc dữ liệu log và cập nhật bảng
    $allLogLines = Get-Content $dataFile | Where-Object { $_ -match "\|" }
    foreach ($logLine in $allLogLines) {
        $parts = $logLine.Split('|')
        if ($parts.Count -lt 5) { continue }

        $m           = $parts[0].Trim()
        $useDate     = $parts[1].Trim()
        $useTime     = $parts[2].Trim()
        $isoGoc      = $parts[3].Trim()
        $isoVietstar = $parts[4].Trim()

        $content = Get-Content $filePath
        $updatedLines = @()
        $foundInMd = $false

        foreach ($line in $content) {
            # So khớp Ngày và Mode để tìm đúng hàng cần tăng Build#
            if ($line -match "^\|\s*${useDate}\s*\|\s*${m}\s*\|") {
                $cols = $line.Split('|') | ForEach-Object { $_.Trim() }
                $oldCounter = if ($cols[3] -as [int]) { [int]$cols[3] } else { 0 }
                $newCounter = $oldCounter + 1
                $updatedLines += "| $useDate | $m | $newCounter | $useTime | $isoGoc | $isoVietstar |"
                $foundInMd = $true
            } else {
                $updatedLines += $line
            }
        }

        if (-not $foundInMd) {
            $updatedLines += "| $useDate | $m | 1 | $useTime | $isoGoc | $isoVietstar |"
        }
        $updatedLines | Set-Content -Path $filePath -Encoding UTF8
    }

    # 4. Git commit & push
    git add "$TargetFile"
    $gitStatus = git status --porcelain "$TargetFile"
    if ($gitStatus) {
        $timestamp = Get-Date -Format "HH:mm:ss"
        git commit -m "Update history $TargetFile at $timestamp [skip ci]"
        
        git push origin master
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[SUCCESS] History pushed."
            Remove-Item $dataFile -ErrorAction SilentlyContinue
            exit 0
        }
        Write-Host "[WARNING] Push failed. Someone might have pushed changes. Retrying..."
    } else {
        Write-Host "[INFO] No changes detected to commit."
        exit 0
    }

    # Nếu xung đột push, đợi rồi thử lại
    Start-Sleep -Seconds (Get-Random -Minimum 5 -Maximum 15)
}