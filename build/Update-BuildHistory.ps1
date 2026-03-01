param(
    [Parameter(Mandatory=$true)]
    [string]$TargetFile, # Ví dụ: "build.md"
    
    [Parameter(Mandatory=$true)]
    [string]$Mode        # auto hoặc manual
)

$ErrorActionPreference = 'Stop'

# 1. Xác định đường dẫn tuyệt đối đến file .md tại thư mục gốc của Repo
$RootPath = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { Get-Location }
$FullFilePath = Join-Path $RootPath $TargetFile
$TempDataFile = Join-Path $RootPath "all_builds_data.txt"

Write-Host "[INFO] Target File: $FullFilePath"

# Kiểm tra nếu không có dữ liệu tạm từ Upload.ps1 thì thoát
if (-not (Test-Path $TempDataFile)) {
    Write-Warning "[WARN] No build data found in $TempDataFile. Skipping update."
    exit 0
}

# 2. Đọc dữ liệu tạm (hỗ trợ nhiều dòng nếu upload nhiều file)
$allLines = Get-Content $TempDataFile -Encoding utf8

# 3. Cấu hình Git
git config user.name "tuthanika-bot"
git config user.email "tuthanika-bot@gmail.com"

# 4. Vòng lặp chống xung đột (Retry Loop - tối đa 10 lần)
for ($i = 1; $i -le 10; $i++) {
    Write-Host "--- Attempt $i: Syncing $TargetFile ---"
    
    # Di chuyển về thư mục gốc để thực hiện các lệnh Git
    Set-Location $RootPath
    
    # Kéo bản mới nhất từ server về (Tránh lỗi non-fast-forward)
    git pull origin $env:GITHUB_REF_NAME --rebase

    # Khởi tạo file nếu chưa tồn tại
    if (-not (Test-Path $FullFilePath)) {
        $header = @"
# Build History

| Date | Mode | Build# | Time | ISO Gốc | ISO VIETSTAR|
|------|------|--------|------|-----------|------------|
"@
        $header | Out-File $FullFilePath -Encoding utf8
    }

    # Đọc nội dung file .md hiện tại
    $content = Get-Content $FullFilePath -Encoding utf8

    # Duyệt qua từng dòng dữ liệu từ Upload.ps1
    foreach ($line in $allLines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        
        # Tách dữ liệu: Date|Time|LocalName|RemoteName
        $parts = $line -split '\|'
        if ($parts.Count -lt 4) { continue }
        
        $B_Date   = $parts[0].Trim()
        $B_Time   = $parts[1].Trim()
        $B_Local  = $parts[2].Trim()
        $B_Remote = $parts[3].Trim()

        # Tìm dòng đã có của Ngày hôm nay + Mode này để tính số Build#
        $pattern = "\|\s$([regex]::Escape($B_Date))\s\|\s$([regex]::Escape($Mode))\s\|"
        $found = $content | Select-String -Pattern $pattern
        
        $newCounter = 1
        if ($found) {
            # Lấy dòng cuối cùng tìm thấy (trường hợp ghi đè hoặc cộng dồn)
            $lastRow = $found | Select-Object -Last 1
            $cols = $lastRow.ToString() -split '\|'
            if ($cols.Count -gt 3) {
                if ([int]::TryParse($cols[3].Trim(), [ref]$oldVal)) {
                    $newCounter = $oldVal + 1
                }
            }
            
            $newLine = "| $B_Date | $Mode | $newCounter | $B_Time | $B_Local | $B_Remote |"
            
            # Tùy chọn: Ghi đè dòng cũ của ngày hôm nay (giống code gốc của bạn)
            $content[$lastRow.LineNumber - 1] = $newLine
        } else {
            # Nếu ngày mới hoàn toàn, thêm dòng mới vào cuối bảng
            $newLine = "| $B_Date | $Mode | 1 | $B_Time | $B_Local | $B_Remote |"
            $content += $newLine
        }
    }

    # Ghi nội dung mới xuống file
    $content | Set-Content $FullFilePath -Encoding utf8

    # 5. Commit và Push
    git add $TargetFile
    
    # Kiểm tra xem có gì để commit không
    git diff --staged --quiet
    if ($LASTEXITCODE -ne 0) {
        $commitMsg = "Lịch sử build VIETSTAR ISO mode $Mode ($(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))"
        git commit -m $commitMsg
        
        git push origin "HEAD:$($env:GITHUB_REF_NAME)"
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[SUCCESS] $TargetFile updated and pushed."
            Remove-Item $TempDataFile -ErrorAction SilentlyContinue
            exit 0
        }
    } else {
        Write-Host "[INFO] No changes to commit."
        Remove-Item $TempDataFile -ErrorAction SilentlyContinue
        exit 0
    }

    # Nếu Push lỗi (do Job khác vừa push xong), đợi ngẫu nhiên rồi thử lại
    $wait = Get-Random -Minimum 3 -Maximum 10
    Write-Host "[RETRY] Conflict detected. Waiting $wait seconds..."
    Start-Sleep -Seconds $wait
}

Write-Error "[ERROR] Failed to update $TargetFile after 10 attempts."
exit 1