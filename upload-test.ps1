param(
    [string[]]$Files
)

Write-Host "Starting upload of files: $Files to $env:RCLONE_PATH..."

# Đường dẫn rclone.exe theo biến SCRIPT_PATH trong YAML
$exePath = Join-Path $env:SCRIPT_PATH "rclone.exe"

foreach ($file in $Files) {
    $arguments = @(
        "copy"
        $file
        $env:RCLONE_PATH
        "--config", $env:RCLONE_CONFIG_PATH
		"--multi-thread-streams=10"
		"--transfers=10"
		"--checkers=10"
		"--tpslimit=10"
		"--tpslimit-burst=15"
        "--progress"
    )

    Write-Host "Uploading $file..."
    Start-Process -FilePath $exePath -ArgumentList $arguments -NoNewWindow -Wait
    Write-Host "Finished uploading $file."
}
