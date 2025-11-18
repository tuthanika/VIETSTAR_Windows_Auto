
setlocal EnableExtensions

set "MODE=%~1"
set "RC=%SCRIPT_PATH%\rclone.exe --config %SCRIPT_PATH%\rclone.conf %rclone_flag%"

:: Lấy folder từ rule.env (đã copy theo mode trước đó)
if not exist "%SCRIPT_PATH%\rule.env" (
  echo [ERROR] rule.env not found
  exit /b 1
)
set "folder="
for /f "usebackq tokens=1,* delims==" %%A in ("%SCRIPT_PATH%\rule.env") do (
  if /I "%%A"=="folder" set "folder=%%B"
)
if "%folder%"=="" (
  echo [ERROR] folder empty in rule.env
  exit /b 1
)

set "_build_md=%SCRIPT_PATH%\BUILD.md"
for /f "delims=" %%TS in ('powershell -NoProfile -Command "Get-Date -f \"yyyy-MM-dd HH:mm:ss\" "') do set "_dt=%%TS"

echo Build mode: %MODE%>> "%_build_md%"
echo Date: %_dt%>> "%_build_md%"
for %%f in ("%SCRIPT_PATH%\%vietstar%\*.iso") do echo Built file: %%~nxf>> "%_build_md%"
echo.>> "%_build_md%"

echo [UPLOAD] To %RCLONE_PATH%/%vietstar%/%folder%
"%RC%" copy "%SCRIPT_PATH%\%vietstar%" "%RCLONE_PATH%/%vietstar%/%folder%" --include "*.iso"
if errorlevel 1 (
  echo [ERROR] Upload failed
  exit /b 1
)

del /q "%SCRIPT_PATH%\%vietstar%\*.iso" 2>nul
echo [UPLOAD] Done
exit /b 0
