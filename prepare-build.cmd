@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: Chuyển codepage về 1252 để tránh vấn đề UTF-8 trên runner
chcp 1252 >nul

set "MODE=%~1"
echo [PREPARE] MODE=%MODE%

set "RC=%SCRIPT_PATH%\rclone.exe --config %SCRIPT_PATH%\rclone.conf %rclone_flag%"

:: Tạo thư mục local
for %%D in ("%SCRIPT_PATH%\%iso%" "%SCRIPT_PATH%\%driver%" "%SCRIPT_PATH%\%boot7%" "%SCRIPT_PATH%\%silent%" "%SCRIPT_PATH%\%vietstar%") do (
  if not exist "%%~D" mkdir "%%~D"
)

:: Đọc rule.env (đã được PowerShell viết sẵn)
if not exist "%SCRIPT_PATH%\rule.env" (
  echo [ERROR] rule.env not found
  exit /b 1
)
for /f "usebackq tokens=1,* delims==" %%A in ("%SCRIPT_PATH%\rule.env") do (
  set "%%A=%%B"
)

:: Các key có thể thiếu: để trống an toàn
if not defined patterns set "patterns="
if not defined folder set "folder="
if not defined drvFolder set "drvFolder="
if not defined drvPatterns set "drvPatterns="
if not defined bootFolder set "bootFolder="
if not defined bootPatterns set "bootPatterns="
if not defined silentFolder set "silentFolder="
if not defined silentPatterns set "silentPatterns="

:: Hàm trích build code (7601.27366)
:extract_build
set "_in=%~1"
set "_outvar=%~2"
set "%_outvar%="
for /f "tokens=1-2 delims=." %%a in ("%_in%") do (
  rem chỉ là placeholder, thực tế build code lấy theo regex; here: fallback none
)
goto :eof

:: Chọn mới nhất theo sort (fallback nếu không có build code)
:choose_latest_simple
set "_remote_dir=%~1"
set "_include=%~2"
set "_outvar=%~3"
set "%_outvar%="
for /f "tokens=2" %%F in ('%RC% ls "%_remote_dir%" --include "%_include%" ^| sort') do (
  set "%_outvar%=%%~nxF"
)
goto :eof

:: Lấy size remote theo tên
:get_remote_size
set "_remote_dir=%~1"
set "_include=%~2"
set "_name=%~3"
set "_outvar=%~4"
set "%_outvar%="
for /f "tokens=1,* delims= " %%S in ('%RC% ls "%_remote_dir%" --include "%_include%"') do (
  for /f "delims=" %%N in ("%%T") do (
    if /I "%%~nxN"=="%_name%" set "%_outvar%=%%S"
  )
)
goto :eof

:: Download có điều kiện (tồn tại + size match)
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
  call :get_remote_size "%_remote_dir%" "%_include%" "%_file%" _remote_size
  if defined _remote_size if "%_local_size%"=="%_remote_size%" (
    echo [PREPARE] Skip download (size match): %_file%
    goto :eof
  )
)
echo [PREPARE] Download %_file%
aria2c -q -d "%_local_dir%" "%_alist_url%"
goto :eof

:: Enforce MAX_FILE trên remote vietstar
:enforce_max
set "_remote_dir=%~1"
set "_include=%~2"
set "_max=%MAX_FILE%"
if "%_max%"=="" set "_max=1"
"%RC%" ls "%_remote_dir%" --include "%_include%" | sort > "%TEMP%\_max_list.txt"
set /a _count=0
for /f "tokens=1,* delims= " %%S in ('type "%TEMP%\_max_list.txt"') do set /a _count+=1
if %_count% LEQ %_max% goto :eof
for /f "skip=%_max% tokens=1,* delims= " %%S in ('type "%TEMP%\_max_list.txt"') do "%RC%" move "%%T" "%_remote_dir%/old/"
goto :eof

:: Bước 0: chọn file nguồn A và bản đã build X
call :choose_latest_simple "%RCLONE_PATH%/%iso%/%folder%" "%patterns%" fileA
call :choose_latest_simple "%RCLONE_PATH%/%vietstar%/%folder%" "%patterns%" fileX

echo [PREPARE] fileA=%fileA%
echo [PREPARE] fileX=%fileX%

:: Nếu tên giống (đơn giản) thì skip
if /I "%fileA%"=="%fileX%" (
  > "%SCRIPT_PATH%\_skip_%MODE%.flag" echo SKIP
  goto set_env
) else (
  call :enforce_max "%RCLONE_PATH%/%vietstar%/%folder%" "%patterns%"
)

:: Bước 1: tải A/B/C/D theo rule (có thể thiếu key)
call :download_if_needed "%RCLONE_PATH%/%iso%/%folder%" "%patterns%" "%SCRIPT_PATH%\%iso%" "%fileA%" "%ALIST_PATH%/%iso%/%folder%/%fileA%"

if defined drvFolder if defined drvPatterns (
  call :choose_latest_simple "%RCLONE_PATH%/%driver%/%drvFolder%" "%drvPatterns%" fileB
  call :download_if_needed "%RCLONE_PATH%/%driver%/%drvFolder%" "%drvPatterns%" "%SCRIPT_PATH%\%driver%" "%fileB%" "%ALIST_PATH%/%driver%/%drvFolder%/%fileB%"
)

if defined bootFolder if defined bootPatterns (
  call :choose_latest_simple "%RCLONE_PATH%/%boot7%" "%bootPatterns%" fileC
  call :download_if_needed "%RCLONE_PATH%/%boot7%" "%bootPatterns%" "%SCRIPT_PATH%\%boot7%" "%fileC%" "%ALIST_PATH%/%boot7%/%fileC%"
)

if defined silentFolder if defined silentPatterns (
  call :choose_latest_simple "%RCLONE_PATH%/%silent%" "%silentPatterns%" fileD
  call :download_if_needed "%RCLONE_PATH%/%silent%" "%silentPatterns%" "%SCRIPT_PATH%\%silent%" "%fileD%" "%ALIST_PATH%/%silent%/%fileD%"
)

:: Bước 2: mount silent nếu có
if defined fileD (
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

:set_env
:: Bước 3: set env cho build chính
set "vietstar=%SCRIPT_PATH%\%vietstar%"
set "oem=%SCRIPT_PATH%\%oem%"
set "dll=%SCRIPT_PATH%\%dll%"
set "driver=%SCRIPT_PATH%\%driver%"
set "iso=%SCRIPT_PATH%\%iso%"
set "boot7=%SCRIPT_PATH%\%boot7%"
set "bootwim=%SCRIPT_PATH%\%bootwim%"

echo [PREPARE] Env OK
exit /b 0
