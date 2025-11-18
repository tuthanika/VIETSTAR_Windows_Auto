@echo off
setlocal enabledelayedexpansion

set "MODE=%~1"
echo [PREPARE] MODE=%MODE%

set "rclone_exe=%SCRIPT_PATH%\rclone.exe"
set "rclone_conf=%SCRIPT_PATH%\rclone.conf"
set "RC=%rclone_exe% --config %rclone_conf% %rclone_flag%"

:: Tạo thư mục local
for %%D in ("%SCRIPT_PATH%\%iso%" "%SCRIPT_PATH%\%driver%" "%SCRIPT_PATH%\%boot7%" "%SCRIPT_PATH%\%silent%" "%SCRIPT_PATH%\%vietstar%") do (
  if not exist "%%~D" mkdir "%%~D"
)

:: Đọc rule theo MODE
echo %FILE_CODE_RULES% > "%TEMP%\rules.json"
for /f "usebackq tokens=*" %%R in (`powershell -NoProfile -Command ^
  "$rules = Get-Content '%TEMP%\rules.json' | ConvertFrom-Json; ^
   ($rules | Where-Object { $_.Mode -eq '%MODE%' }) | ConvertTo-Json -Compress"`) do set "rule=%%R"
if "%rule%"=="" (
  echo [ERROR] Không tìm thấy rule cho MODE=%MODE%
  exit /b 1
)

for /f "usebackq tokens=*" %%P in (`powershell -NoProfile -Command ^
  "$r = %rule% | ConvertFrom-Json; $r.Patterns -join ';'"`) do set "patterns=%%P"
for /f "usebackq tokens=*" %%F in (`powershell -NoProfile -Command ^
  "$r = %rule% | ConvertFrom-Json; $r.Folder"`) do set "folder=%%F"
for /f "usebackq tokens=*" %%DP in (`powershell -NoProfile -Command ^
  "$r = %rule% | ConvertFrom-Json; $r.DriverPatterns -join ';'"`) do set "drvPatterns=%%DP"
for /f "usebackq tokens=*" %%DF in (`powershell -NoProfile -Command ^
  "$r = %rule% | ConvertFrom-Json; $r.DriverFolder"`) do set "drvFolder=%%DF"
for /f "usebackq tokens=*" %%BP in (`powershell -NoProfile -Command ^
  "$r = %rule% | ConvertFrom-Json; $r.BootPatterns -join ';'"`) do set "bootPatterns=%%BP"
for /f "usebackq tokens=*" %%BF in (`powershell -NoProfile -Command ^
  "$r = %rule% | ConvertFrom-Json; $r.BootFolder"`) do set "bootFolder=%%BF"
for /f "usebackq tokens=*" %%SP in (`powershell -NoProfile -Command ^
  "$r = %rule% | ConvertFrom-Json; $r.SilentPatterns -join ';'"`) do set "silentPatterns=%%SP"
for /f "usebackq tokens=*" %%SF in (`powershell -NoProfile -Command ^
  "$r = %rule% | ConvertFrom-Json; $r.SilentFolder"`) do set "silentFolder=%%SF"

echo [PREPARE] Folder=%folder%
echo [PREPARE] Patterns=%patterns%
echo [PREPARE] DriverFolder=%drvFolder% DriverPatterns=%drvPatterns%
echo [PREPARE] BootFolder=%bootFolder% BootPatterns=%bootPatterns%
echo [PREPARE] SilentFolder=%silentFolder% SilentPatterns=%silentPatterns%

:: Hàm: trích build code (ví dụ 7601.27366)
:extract_build
set "_in=%~1"
for /f "usebackq delims=" %%B in (`powershell -NoProfile -Command "$f='%_in%'; $m=[regex]::Match($f,'\d{4}\.\d+'); if($m.Success){$m.Value} else {''}"`) do set "%2=%%B"
goto :eof

:: Hàm: lấy size remote của 1 file (rclone ls trả size + path)
:get_remote_size
set "_remote_dir=%~1"
set "_include=%~2"
set "_name=%~3"
set "_size_outvar=%~4"
set "%_size_outvar%="
for /f "tokens=1,* delims= " %%S in ('%RC% ls "%_remote_dir%" --include "%_include%"') do (
  for /f "delims=" %%N in ("%%T") do (
    if /I "%%~nxN"=="%_name%" set "%_size_outvar%=%%S"
  )
)
goto :eof

:: Hàm: chọn file mới nhất theo build code
:choose_latest_by_build
set "_list_dir=%~1"
set "_include=%~2"
set "_outvar=%~3"
set "_bestFN="
set "_bestBuild="
for /f "tokens=1,* delims= " %%S in ('%RC% ls "%_list_dir%" --include "%_include%"') do (
  for /f "delims=" %%N in ("%%T") do (
    set "_fn=%%~nxN"
    call :extract_build "!_fn!" _curBuild
    if not "!_curBuild!"=="" (
      if "!_bestBuild!"=="" (
        set "_bestBuild=!_curBuild!"
        set "_bestFN=!_fn!"
      ) else (
        for /f "tokens=1,2 delims=." %%a in ("!_curBuild!") do set "_curMajor=%%a" & set "_curMinor=%%b"
        for /f "tokens=1,2 delims=." %%a in ("!_bestBuild!") do set "_bestMajor=%%a" & set "_bestMinor=%%b"
        if "!_curMajor!" gtr "!_bestMajor!" (
          set "_bestBuild=!_curBuild!"
          set "_bestFN=!_fn!"
        ) else if "!_curMajor!"=="!_bestMajor!" (
          if "!_curMinor!" gtr "!_bestMinor!" (
            set "_bestBuild=!_curBuild!"
            set "_bestFN=!_fn!"
          )
        )
      )
    )
  )
)
if "!_bestFN!"=="" (
  for /f "tokens=2" %%A in ('%RC% ls "%_list_dir%" --include "%_include%" ^| sort') do set "_bestFN=%%~nxA"
)
set "%_outvar%=%_bestFN%"
goto :eof

:: Hàm: download có điều kiện (kiểm tra tồn tại và size khớp)
:download_if_needed
set "_remote_dir=%~1"
set "_include=%~2"
set "_local_dir=%~3"
set "_file=%~4"
set "_alist_url=%~5"
if "%_file%"=="" (
  echo [PREPARE] Không có file để tải trên %_remote_dir%
  goto :eof
)
if not exist "%_local_dir%" mkdir "%_local_dir%"
set "_local_file=%_local_dir%\%_file%"

if exist "%_local_file%" (
  for %%Z in ("%_local_file%") do set "_local_size=%%~zZ"
  call :get_remote_size "%_remote_dir%" "%_include%" "%_file%" _remote_size
  if not "%_remote_size%"=="" (
    echo [PREPARE] So sánh size local=%_local_size% vs remote=%_remote_size% cho %_file%
    if "%_local_size%"=="%_remote_size%" (
      echo [PREPARE] Bỏ qua tải vì trùng size: %_file%
      goto :eof
    )
  )
)
echo [PREPARE] Tải %_file% -> %_local_dir%
aria2c -q -d "%_local_dir%" "%_alist_url%"
goto :eof

:: Hàm: enforce MAX_FILE (giữ lại mới nhất theo sort, di chuyển phần dư vào old/)
:enforce_max
set "_remote_dir=%~1"
set "_include=%~2"
set "_max=%MAX_FILE%"
if "%_max%"=="" set "_max=1"
echo [PREPARE] Enforce MAX_FILE=%_max% trên %_remote_dir%
"%RC%" ls "%_remote_dir%" --include "%_include%" | sort > "%TEMP%\_max_list.txt"
set /a _count=0
for /f "tokens=1,* delims= " %%S in ('type "%TEMP%\_max_list.txt"') do set /a _count+=1
if %_count% LEQ %_max% (
  echo [PREPARE] Không cần prune (count=%_count%)
  goto :eof
)
set /a _toMove=%_count% - %_max%
echo [PREPARE] Di chuyển %_toMove% bản cũ vào old/
for /f "skip=%_max% tokens=1,* delims= " %%S in ('type "%TEMP%\_max_list.txt"') do "%RC%" move "%%T" "%_remote_dir%/old/"
goto :eof

:: Bước 0: chọn file A (ISO nguồn) và file X (đã build)
call :choose_latest_by_build "%RCLONE_PATH%/%iso%/%folder%" "%patterns%" fileA
call :choose_latest_by_build "%RCLONE_PATH%/%vietstar%/%folder%" "%patterns%" fileX

echo [PREPARE] fileA=%fileA%
echo [PREPARE] fileX=%fileX%

set "buildA="
set "buildX="
if not "%fileA%"=="" call :extract_build "%fileA%" buildA
if not "%fileX%"=="" call :extract_build "%fileX%" buildX
echo [PREPARE] buildA=%buildA% buildX=%buildX%

if not "%buildA%"=="" if not "%buildX%"=="" (
  if /I "%buildA%"=="%buildX%" (
    echo [PREPARE] Build code trùng → tạo skip flag và bỏ qua build
    > "%SCRIPT_PATH%\_skip_%MODE%.flag" echo SKIP
    goto set_env
  ) else (
    echo [PREPARE] Build khác nhau → enforce MAX_FILE và tiếp tục
    call :enforce_max "%RCLONE_PATH%/%vietstar%/%folder%" "%patterns%"
  )
)

:: Bước 1: tải A/B/C/D với logic “kiểm tra tồn tại + so sánh size” (tải có điều kiện)
call :download_if_needed "%RCLONE_PATH%/%iso%/%folder%" "%patterns%" "%SCRIPT_PATH%\%iso%" "%fileA%" "%ALIST_PATH%/%iso%/%folder%/%fileA%"

:: B: Driver
call :choose_latest_by_build "%RCLONE_PATH%/%driver%/%drvFolder%" "%drvPatterns%" fileB
echo [PREPARE] fileB=%fileB%
call :download_if_needed "%RCLONE_PATH%/%driver%/%drvFolder%" "%drvPatterns%" "%SCRIPT_PATH%\%driver%" "%fileB%" "%ALIST_PATH%/%driver%/%drvFolder%/%fileB%"

:: C: Boot (dùng chung giữa các mode → vẫn dùng logic kiểm tra tồn tại)
call :choose_latest_by_build "%RCLONE_PATH%/%boot7%" "%bootPatterns%" fileC
echo [PREPARE] fileC=%fileC%
call :download_if_needed "%RCLONE_PATH%/%boot7%" "%bootPatterns%" "%SCRIPT_PATH%\%boot7%" "%fileC%" "%ALIST_PATH%/%boot7%/%fileC%"

:: D: Silent (dùng chung giữa các mode → kiểm tra tồn tại)
call :choose_latest_by_build "%RCLONE_PATH%/%silent%" "%silentPatterns%" fileD
echo [PREPARE] fileD=%fileD%
call :download_if_needed "%RCLONE_PATH%/%silent%" "%silentPatterns%" "%SCRIPT_PATH%\%silent%" "%fileD%" "%ALIST_PATH%/%silent%/%fileD%"

:: Bước 2: mount silent D vào A:
if not "%fileD%"=="" (
  imdisk -D -m A: >nul 2>&1
  imdisk -a -m A: -f "%SCRIPT_PATH%\%silent%\%fileD%"
  if errorlevel 1 (
    echo [WARN] Mount silent thất bại, dùng path silent mặc định
    set "silent=%SCRIPT_PATH%\%silent%"
  ) else (
    set "silent=A:\Silent\VIETSTAR-Silent-Network\Apps\exe"
  )
) else (
  set "silent=%SCRIPT_PATH%\%silent%"
)

:set_env
:: Bước cuối: set env để cmd build chính nhận diện
set "vietstar=%SCRIPT_PATH%\%vietstar%"
set "oem=%SCRIPT_PATH%\%oem%"
set "dll=%SCRIPT_PATH%\%dll%"
set "driver=%SCRIPT_PATH%\%driver%"
set "iso=%SCRIPT_PATH%\%iso%"
set "boot7=%SCRIPT_PATH%\%boot7%"
set "bootwim=%SCRIPT_PATH%\%bootwim%"

echo [PREPARE] Env:
echo   vietstar=%vietstar%
echo   silent=%silent%
echo   oem=%oem%
echo   dll=%dll%
echo   driver=%driver%
echo   iso=%iso%
echo   boot7=%boot7%
echo   bootwim=%bootwim%

exit /b 0
