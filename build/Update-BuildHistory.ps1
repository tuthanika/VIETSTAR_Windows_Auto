param(
    [string]$TargetFile,
    [string]$Mode
)

$tempDataFile = Join-Path $env:GITHUB_WORKSPACE "all_builds_data.txt"
if (-not (Test-Path $tempDataFile)) { 
    Write-Host "No build data to update."; exit 0 
}

$allLines = Get-Content $tempDataFile
git config user.name "tuthanika-bot"
git config user.email "tuthanika-bot@gmail.com"

for ($i = 1; $i -le 10; $i++) {
    Write-Host "Attempt $i: Updating $TargetFile..."
    git pull origin $env:GITHUB_REF_NAME --rebase

    # Đảm bảo file md tồn tại
    if (-not (Test-Path $TargetFile)) {
        @"`
# Build History

| Date | Mode | Build# | Time | ISO Gốc | ISO VIETSTAR|
|------|------|--------|------|-----------|------------|
"@ | Out-File $TargetFile -Encoding utf8
    }

    # Xử lý từng dòng dữ liệu từ file tạm
    $content = Get-Content $TargetFile -Encoding utf8
    
    foreach ($line in $allLines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split '\|'
        $B_Date = $parts[0]; $B_Time = $parts[1]; $B_Local = $parts[2]; $B_Remote = $parts[3]

        # Tìm dòng cũ để tính Counter
        $pattern = "\|\s$($B_Date)\s\|\s$($Mode)\s\|"
        $found = $content | Select-String -Pattern $pattern
        
        $newCounter = 1
        if ($found) {
            $lastRow = $found | Select-Object -Last 1 # Lấy dòng mới nhất của ngày đó
            $cols = $lastRow.ToString() -split '\|'
            $newCounter = [int]($cols[3].Trim()) + 1
            
            $newLine = "| $B_Date | $Mode | $newCounter | $B_Time | $B_Local | $B_Remote |"
            # Thay thế hoặc chèn thêm (tùy bạn muốn ghi đè dòng cùng ngày hay thêm mới)
            # Ở đây ta chọn THÊM MỚI nếu muốn lưu lịch sử chi tiết từng file trong ngày
            $content += $newLine 
        } else {
            $newLine = "| $B_Date | $Mode | 1 | $B_Time | $B_Local | $B_Remote |"
            $content += $newLine
        }
    }

    $content | Set-Content $TargetFile -Encoding utf8

    # Commit và Push
    git add $TargetFile
    git diff --staged --quiet
    if ($LASTEXITCODE -ne 0) {
		git commit -m "Lịch sử build VIETSTAR ISO mode $Mode ($(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))"
        git push origin "HEAD:$($env:GITHUB_REF_NAME)"
        if ($LASTEXITCODE -eq 0) { 
            Remove-Item $tempDataFile # Xong thì xóa file tạm
            exit 0 
        }
    } else {
        exit 0 # Không có gì thay đổi
    }

    Start-Sleep -Seconds (Get-Random -Minimum 3 -Maximum 10)
}