@echo on
setlocal EnableExtensions EnableDelayedExpansion

:: ===== DEBUG START =====
echo [DEBUG] upload-build.cmd started
echo [DEBUG] MODE arg: "%~1"
:: ===== DEBUG END =======

set "MODE=%~1"
set "RC=%SCRIPT_PATH%\rclone.exe --config %SCRIPT_PATH%\rclone.conf %rclone_flag%"

:: Đọc folder từ rule.env (được prepare-build.cmd hoặc step trước đó đặt sẵn)
if not exist "%SCRIPT_PATH%\rule.env" (
  echo [ERROR] rule.env not found at "%SCRIPT_PATH%\rule.env"
  dir "%SCRIPT_PATH%"
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

:: Tạo timestamp an toàn bằng batch (không PowerShell)
:: Format: YYYY-MM-DD HH:MM:SS
for /f "tokens=1-3 delims=/-. " %%a in ("%date%") do (
  set "YYYY=%%c"
  set "MM=%%b"
  set "DD=%%a"
)
set "_time=%time%"
:: zero-pad milliseconds drift by removing commas/spaces
for /f "tokens=1-3 delims=:." %%x in ("%_time%") do (
  set "HH=%%x"
  set "MIN=%%y"
  set "SEC=%%z"
)
:: Một số runner có HH bắt đầu bằng space → trim
if "!HH:~0,1!"==" " set "HH=!HH:~1!"
set "_dt=%YYYY%-%MM%-%DD% %HH%:%MIN%:%SEC%"

echo [DEBUG] Timestamp: !_dt!

set "_build_md=%SCRIPT_PATH%\BUILD.md"

echo Build mode: %MODE%>> "%_build_md%"
echo Date: !_dt!>> "%_build_md%"
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
