param(
    [Parameter(Mandatory=$true)]
    [string]$TargetFile
)

$filePath = Join-Path $env:SCRIPT_PATH $TargetFile
$dataFile = Join-Path $env:GITHUB_WORKSPACE "all_builds_data.txt"
$now = Get-Date
$dateStr = $now.ToString("dd-MM-yyyy")

# Cấu hình Git
git config --global user.name "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"

# Retry loop để chống xung đột Git push
for ($i = 1; $i -le 10; $i++) {
    Write-Host "[RETRY $i/10] Pulling latest history..."
    git pull origin $env:GITHUB_REF_NAME --rebase

    if (-not (Test-Path $filePath)) {
        $header = "| Date | Mode | Build# | Time | ISO Gốc | ISO VIETSTAR |`n|---|---|---|---|---|---|"
        Set-Content -Path $filePath -Value $header -Encoding UTF8
    }

    # KIỂM TRA FILE LOG: Nếu không có log nào (do tất cả các mode đều bị SKIP)
    if (-not (Test-Path $dataFile)) {
        Write-Host "[INFO] No build data found in $dataFile (All modes might be skipped)."
        exit 0
    }

    # ĐỌC TRỰC TIẾP TỪNG DÒNG TRONG FILE LOG
    $allLogLines = Get-Content $dataFile
    foreach ($logLine in $allLogLines) {
        $parts = $logLine.Split('|')
        if ($parts.Count -lt 5) { continue }

        $m           = $parts[0].Trim() # Mode
        $useDate     = $parts[1].Trim() # Date từ log (đã sửa ở Upload.ps1 là dd-MM-yyyy)
        $useTime     = $parts[2].Trim() # Time từ log
        $isoGoc      = $parts[3].Trim() # LocalName
        $isoVietstar = $parts[4].Trim() # RemoteName

        $content = Get-Content $filePath
        $updatedLines = @()
        $foundInMd = $false

        foreach ($line in $content) {
            # So sánh Mode ở cột 2 trong build.md
            if ($line -match "^\|\s*[^|]*\s*\|\s*${m}\s*\|") {
                $cols = $line.Split('|') | ForEach-Object { $_.Trim() }
                $oldDate = $cols[1]
                $oldCounter = [int]$cols[3]

                # Logic Build#: Cùng ngày tăng, khác ngày reset
                $newCounter = if ($oldDate -eq $useDate) { $oldCounter + 1 } else { 1 }

                $updatedLines += "| $useDate | $m | $newCounter | $useTime | $isoGoc | $isoVietstar |"
                $foundInMd = $true
            } else {
                # Không phải mode này thì giữ nguyên
                $updatedLines += $line
            }
        }

        # Nếu Mode này chưa có trong build.md thì thêm mới
        if (-not $foundInMd) {
            $updatedLines += "| $useDate | $m | 1 | $useTime | $isoGoc | $isoVietstar |"
        }

        # Lưu lại để dùng cho dòng log tiếp theo (nếu có nhiều mode trong 1 lần build)
        $updatedLines | Set-Content -Path $filePath -Encoding UTF8
    }

    # Thực hiện Push
    git add $TargetFile
    if (git status --porcelain) {
        git commit -m "Update build history from log [skip ci]"
        git push origin "HEAD:$($env:GITHUB_REF_NAME)"
        if ($LASTEXITCODE -eq 0) { 
            Write-Host "[SUCCESS] Updated history successfully."
            # Quan trọng: Xóa file log sau khi đã ghi thành công để Job sau không đọc lại dữ liệu cũ
            Remove-Item $dataFile -ErrorAction SilentlyContinue
            exit 0 
        }
    } else {
        Write-Host "[INFO] No changes to commit."; exit 0
    }
    Start-Sleep -Seconds (Get-Random -Minimum 3 -Maximum 10)
}
exit 1