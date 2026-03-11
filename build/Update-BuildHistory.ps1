param(
    [Parameter(Mandatory=$true)]
    [string]$TargetFile
)

$ErrorActionPreference = 'Stop'
$RootPath = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { Get-Location }
$FullFilePath = Join-Path $RootPath $TargetFile
$TempDataFile = Join-Path $RootPath "all_builds_data.txt"

if (-not (Test-Path $TempDataFile)) { exit 0 }

$allLines = Get-Content $TempDataFile -Encoding utf8
git config user.name "tuthanika-bot"
git config user.email "tuthanika-bot@gmail.com"

for ($i = 1; $i -le 10; $i++) {
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
        if ($parts.Count -lt 5) { continue }
        
        $B_Date   = $parts[0].Trim()
        $B_Mode   = $parts[1].Trim()
        $B_Time   = $parts[2].Trim()
        $B_Local  = $parts[3].Trim()
        $B_Remote = $parts[4].Trim()

        # LOGIC MỚI: Chỉ tìm theo Mode (Không quan tâm ngày cũ là ngày nào)
        # Pattern này tìm dòng có Mode nằm giữa 2 dấu gạch đứng
        $pattern = "\|\s.*\s\|\s$([regex]::Escape($B_Mode))\s\|"
        $found = $content | Select-String -Pattern $pattern
        
        if ($found) {
            $lineIdx = $found[0].LineNumber - 1
            $cols = $content[$lineIdx] -split '\|'
            
            $oldDate = $cols[1].Trim()
            $oldBuildCount = if ($cols.Count -gt 3) { [int]($cols[3].Trim()) } else { 0 }

            # Kiểm tra ngày
            if ($oldDate -eq $B_Date) {
                # Cùng ngày: Tăng số Build#
                $newCounter = $oldBuildCount + 1
            } else {
                # Khác ngày: Reset số Build# về 1
                $newCounter = 1
            }
            
            # Ghi đè (Replace) hàng cũ bằng dữ liệu mới
            $newLine = "| $B_Date | $B_Mode | $newCounter | $B_Time | $B_Local | $B_Remote |"
            $content[$lineIdx] = $newLine
            Write-Host "[UPDATE] Mode ${B_Mode}: Ngày ${B_Date}, Build #${newCounter}"
        } else {
            # Nếu chưa từng có Mode này trong file: Thêm dòng mới
            $newLine = "| $B_Date | $B_Mode | 1 | $B_Time | $B_Local | $B_Remote |"
            $content += $newLine
            Write-Host "[NEW] Mode ${B_Mode} added."
        }
    }

    $content | Set-Content $FullFilePath -Encoding utf8

    git add $TargetFile
    git diff --staged --quiet
    if ($LASTEXITCODE -ne 0) {
        git commit -m "Auto update ${TargetFile} ($(Get-Date -Format 'dd-MM-yyyy HH:mm'))"
        git push origin "HEAD:$($env:GITHUB_REF_NAME)"
        if ($LASTEXITCODE -eq 0) {
            Remove-Item $TempDataFile -ErrorAction SilentlyContinue
            exit 0
        }
    } else {
        Remove-Item $TempDataFile -ErrorAction SilentlyContinue
        exit 0
    }
    Start-Sleep -Seconds (Get-Random -Minimum 3 -Maximum 10)
}

exit 1