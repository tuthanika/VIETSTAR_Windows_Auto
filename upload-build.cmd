@echo on
setlocal EnableExtensions EnableDelayedExpansion

echo [DEBUG] upload-build.cmd started
echo [DEBUG] MODE arg: "%~1"

set "MODE=%~1"
set "RC=%SCRIPT_PATH%\rclone.exe --config %SCRIPT_PATH%\rclone.conf %rclone_flag%"

if not exist "%SCRIPT_PATH%\rule.env" (
  echo [ERROR] rule.env not found at "%SCRIPT_PATH%\rule.env"
  exit /b 1
)

