@echo off
setlocal enabledelayedexpansion

set "MODE=%~1"
echo [PREPARE] MODE=%MODE%

set "RC=%SCRIPT_PATH%\rclone.exe --config %SCRIPT_PATH%\rclone.conf %rclone_flag%"

:: Tạo thư mục local
for %%D in ("%SCRIPT_PATH%\%iso%" "%SCRIPT_PATH%\%driver%" "%SCRIPT_PATH%\%boot7%" "%SCRIPT_PATH%\%silent%" "%SCRIPT_PATH%\%vietstar%") do (
  if not exist "%%~D" mkdir "%%~D"
)

:: Đọc rule theo MODE
echo %FILE_CODE_RULES% > "%TEMP%\rules.json"
for /f "usebackq tokens=*" %%R in (`powershell -NoProfile -Command ^
  "$rules = Get-Content '%TEMP%\rules.json' | ConvertFrom-Json; ^
   ($rules | Where-Object { $_.Mode -eq '%MODE%' }) | ConvertTo-Json -Compress"`) do set "rule=%%R"

:: Lấy các key, nếu không có thì sẽ rỗng
for /f "usebackq tokens=*" %%P in (`powershell -NoProfile -Command ^
  "$r = %rule% | ConvertFrom-Json; if($r.Patterns){$r.Patterns -join ';'}"`) do set "patterns=%%P"
for /f "usebackq tokens=*" %%F in (`powershell -NoProfile -Command ^
  "$r = %rule% | ConvertFrom-Json; if($r.Folder){$r.Folder}"`) do set "folder=%%F"
for /f "usebackq tokens=*" %%DP in (`powershell -NoProfile -Command ^
  "$r = %rule% | ConvertFrom-Json; if($r.DriverPatterns){$r.DriverPatterns -join ';'}"`) do set "drvPatterns=%%DP"
for /f "usebackq tokens=*" %%DF in (`powershell -NoProfile -Command ^
  "$r = %rule% | ConvertFrom-Json; if($r.DriverFolder){$r.DriverFolder}"`) do set "drvFolder=%%DF"
for /f "usebackq tokens=*" %%BP in (`powershell -NoProfile -Command ^
  "$r = %rule% | ConvertFrom-Json; if($r.BootPatterns){$r.BootPatterns -join ';'}"`) do set "bootPatterns=%%BP"
for /f "usebackq tokens=*" %%BF in (`powershell -NoProfile -Command ^
  "$r = %rule% | ConvertFrom-Json; if($r.BootFolder){$r.BootFolder}"`) do set "bootFolder=%%BF"
for /f "usebackq tokens=*" %%SP in (`powershell -NoProfile -Command ^
  "$r = %rule% | ConvertFrom-Json; if($r.SilentPatterns){$r.SilentPatterns -join ';'}"`) do set "silentPatterns=%%SP"
for /f "usebackq tokens=*" %%SF in (`powershell -NoProfile -Command ^
  "$r = %rule% | ConvertFrom-Json; if($r.SilentFolder){$r.SilentFolder}"`) do set "silentFolder=%%SF"

:: Hàm download có điều kiện
:download_if_needed
set "_remote_dir=%~1"
set "_include=%~2"
set "_local_dir=%~3"
set "_file=%~4"
set "_alist_url=%~5"
if "%_file%"=="" goto :eof
if not exist "%_local_dir%" mkdir "%_local_dir%"
set "_local_file=%_local_dir%\%_file%"
if exist "%_local_file%" (
  for %%Z in ("%_local_file%") do set "_local_size=%%~zZ"
  set "_remote_size="
  for /f "tokens=1,* delims= " %%S in ('%RC% ls "%_remote_dir%" --include "%_include%"') do (
    if /I "%%~nxT"=="%_file%" set "_remote_size=%%S"
  )
  if "%_local_size%"=="%_remote_size%" (
    echo [PREPARE] Bỏ qua tải vì trùng size: %_file%
    goto :eof
  )
)
echo [PREPARE] Tải %_file%
aria2c -q -d "%_local_dir%" "%_alist_url%"
goto :eof

:: Sau khi định nghĩa hàm, gọi tải từng loại file
call :download_if_needed "%RCLONE_PATH%/%iso%/%folder%" "%patterns%" "%SCRIPT_PATH%\%iso%" "%fileA%" "%ALIST_PATH%/%iso%/%folder%/%fileA%"

if not "%drvFolder%"=="" if not "%drvPatterns%"=="" (
  call :choose_latest_by_build "%RCLONE_PATH%/%driver%/%drvFolder%" "%drvPatterns%" fileB
  call :download_if_needed "%RCLONE_PATH%/%driver%/%drvFolder%" "%drvPatterns%" "%SCRIPT_PATH%\%driver%" "%fileB%" "%ALIST_PATH%/%driver%/%drvFolder%/%fileB%"
)

if not "%bootFolder%"=="" if not "%bootPatterns%"=="" (
  call :choose_latest_by_build "%RCLONE_PATH%/%boot7%" "%bootPatterns%" fileC
  call :download_if_needed "%RCLONE_PATH%/%boot7%" "%bootPatterns%" "%SCRIPT_PATH%\%boot7%" "%fileC%" "%ALIST_PATH%/%boot7%/%fileC%"
)

if not "%silentFolder%"=="" if not "%silentPatterns%"=="" (
  call :choose_latest_by_build "%RCLONE_PATH%/%silent%" "%silentPatterns%" fileD
  call :download_if_needed "%RCLONE_PATH%/%silent%" "%silentPatterns%" "%SCRIPT_PATH%\%silent%" "%fileD%" "%ALIST_PATH%/%silent%/%fileD%"
)

:: Mount silent nếu có
if not "%fileD%"=="" (
  imdisk -D -m A: >nul 2>&1
  imdisk -a -m A: -f "%SCRIPT_PATH%\%silent%\%fileD%"
  if errorlevel 1 (
    set "silent=%SCRIPT_PATH%\%silent%"
  ) else (
    set "silent=A:\Silent\VIETSTAR-Silent-Network\Apps\exe"
  )
) else (
  set "silent=%SCRIPT_PATH%\%silent%"
)

:: Set env cho build chính
set "vietstar=%SCRIPT_PATH%\%vietstar%"
set "oem=%SCRIPT_PATH%\%oem%"
set "dll=%SCRIPT_PATH%\%dll%"
set "driver=%SCRIPT_PATH%\%driver%"
set "iso=%SCRIPT_PATH%\%iso%"
set "boot7=%SCRIPT_PATH%\%boot7%"
set "bootwim=%SCRIPT_PATH%\%bootwim%"

echo [PREPARE] Env đã set xong
exit /b 0
