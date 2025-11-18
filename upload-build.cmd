@echo on
setlocal EnableExtensions EnableDelayedExpansion

echo [DEBUG] upload-build.cmd started
echo [DEBUG] MODE arg: "%~1"

set "MODE=%~1"
set "RC=%SCRIPT_PATH%\rclone.exe --config %SCRIPT_PATH%\rclone.conf %rclone_flag%"

:: Đọc folder từ rule.env
if not exist "%SCRIPT_PATH%\rule.env" (
  echo [ERROR] rule.env not found at "%SCRIPT_PATH%\rule.env"
  exit /b 1
)

set "folder="
for /f "usebackq tokens=1,* delims==" %%A in ("%SCRIPT_PATH%\rule.env") do (
  if /I "%%A"=="folder" set "folder=%%B"
)

if "%folder%"=="" (
  echo [ERROR] "folder" is empty in rule.env
  type "%SCRIPT_PATH%\rule.env"
  exit /b 1
)

:: Lấy timestamp bằng PowerShell để tránh lỗi parse %date%
for /f "usebackq tokens=*" %%A in (`powershell -NoProfile -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"`) do set "_dt=%%A"
echo [DEBUG] Timestamp: %_dt%

set "_build_md=%SCRIPT_PATH%\BUILD.md"

echo Build mode: %MODE%>> "%_build_md%"
echo Date: %_dt%>> "%_build_md%"
for %%f in ("%SCRIPT_PATH%\%vietstar%\*.iso") do echo Built file: %%~nxf>> "%_build_md%"
echo.>> "%_build_md%"

echo [UPLOAD] To %RCLONE_PATH%/%vietstar%/%folder%
"%RC%" copy "%SCRIPT_PATH%\%vietstar%" "%RCLONE_PATH%/%vietstar%/%folder%" --include "*.iso"
if errorlevel 1 (
  echo [ERROR] Upload failed (rclone copy errorlevel=%errorlevel%)
  exit /b 1
)

echo [CLEANUP] Deleting local ISO
del /q "%SCRIPT_PATH%\%vietstar%\*.iso" 2>nul

echo [UPLOAD] Done
exit /b 0
