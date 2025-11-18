@echo off
setlocal enabledelayedexpansion

set "MODE=%~1"
set "RC=%SCRIPT_PATH%\rclone.exe --config %SCRIPT_PATH%\rclone.conf %rclone_flag%"

:: Lay folder upload theo rule
echo %FILE_CODE_RULES% > "%TEMP%\rules.json"
for /f "usebackq tokens=*" %%F in (`powershell -NoProfile -Command ^
  "$rules = Get-Content '%TEMP%\rules.json' ^| ConvertFrom-Json; ^
   ($rules ^| Where-Object { $_.Mode -eq '%MODE%' }).Folder"`) do set "targetFolder=%%F"

if "%targetFolder%"=="" (
  echo [ERROR] Không tìm thấy Folder cho MODE=%MODE%
  exit /b 1
)

set "_build_md=%SCRIPT_PATH%\BUILD.md"
for /f "delims=" %%TS in ('powershell -NoProfile -Command "Get-Date -f \"yyyy-MM-dd HH:mm:ss\" "') do set "_dt=%%TS"

echo Build mode: %MODE%>> "%_build_md%"
echo Date: %_dt%>> "%_build_md%"
for %%f in ("%SCRIPT_PATH%\%vietstar%\*.iso") do echo Built file: %%~nxf>> "%_build_md%"
echo.>> "%_build_md%"

echo [UPLOAD] Upload lên %RCLONE_PATH%/%vietstar%/%targetFolder%
"%RC%" copy "%SCRIPT_PATH%\%vietstar%" "%RCLONE_PATH%/%vietstar%/%targetFolder%" --include "*.iso"
if errorlevel 1 (
  echo [ERROR] Upload thất bại
  exit /b 1
)

echo [UPLOAD] Xóa file local sau upload
del /q "%SCRIPT_PATH%\%vietstar%\*.iso" 2>nul

echo [UPLOAD] Done
exit /b 0
