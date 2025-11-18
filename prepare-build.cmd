@echo off
setlocal enabledelayedexpansion

set "MODE=%~1"
echo [PREPARE] MODE=%MODE%

set "rclone_exe=%SCRIPT_PATH%\rclone.exe"
set "rclone_conf=%SCRIPT_PATH%\rclone.conf"
set "RC=%rclone_exe% --config %rclone_conf% %rclone_flag%"

:: Tạo thư mục local bắt buộc
for %%D in ("%SCRIPT_PATH%\%iso%" "%SCRIPT_PATH%\%driver%" "%SCRIPT_PATH%\%boot7%" "%SCRIPT_PATH%\%silent%" "%SCRIPT_PATH%\%vietstar%") do (
  if not exist "%%~D" mkdir "%%~D"
)

:: Lấy rule theo MODE
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

echo [PREPARE] Patterns=%patterns%
echo [PREPARE] Folder=%folder%

:: Hàm: trích build code dạng 4 chữ số.chuỗi số (ví dụ 7601.27366)
:extract_build
set "_in=%~1"
for /f "usebackq delims=" %%B in (`powershell -NoProfile -Command "$f='%_in%'; $m=[regex]::Match($f,'\d{4}\.\d+'); if($m.Success){$m.Value} else {''}"`) do set "%2=%%B"
goto :eof

:: Hàm: chọn bản có build code lớn nhất trong danh sách rclone ls
:choose_latest_by_build
set "_list=%~1"
set "_outvar=%~2"
set "_bestFN="
set "_bestBuild="
for /f "tokens=1,* delims= " %%S in ('type "%_list%"') do (
  set "_path=%%T"
  for /f "delims=" %%N in ("!_path!") do (
    for /f "delims=" %%F in ("%%~nxN") do (
      call :extract_build "%%F" _curBuild
      if not "!_curBuild!"=="" (
        if "!_bestBuild!"=="" (
          set "_bestBuild=!_curBuild!"
          set "_bestFN=%%F"
        ) else (
          for /f "tokens=1,2 delims=." %%a in ("!_curBuild!") do set "_curMajor=%%a" & set "_curMinor=%%b"
          for /f "tokens=1,2 delims=." %%a in ("!_bestBuild!") do set "_bestMajor=%%a" & set "_bestMinor=%%b"
          if "!_curMajor!" gtr "!_bestMajor!" (
            set "_bestBuild=!_curBuild!"
            set "_bestFN=%%F"
          ) else if "!_curMajor!"=="!_bestMajor!" (
            if "!_curMinor!" gtr "!_bestMinor!" (
              set "_bestBuild=!_curBuild!"
              set "_bestFN=%%F"
            )
          )
        )
      )
    )
  )
)
set "%_outvar%=%_bestFN%"
goto :eof

:: Hàm: chọn file đầu tiên nếu không có build code
:choose_first_name
set "_list=%~1"
set "_outvar=%~2"
set "_firstFN="
for /f "tokens=1,* delims= " %%S in ('type "%_list%"') do (
  set "_path=%%T"
  for /f "delims=" %%N in ("!_path!") do (
    set "_firstFN=%%~nxN"
    goto :choose_first_name_done
  )
)
:choose_first_name_done
set "%_outvar%=%_firstFN%"
goto :eof

:: Hàm: enforce MAX_FILE trên remote vietstar, di chuyển file cũ vào thư mục old
:enforce_max
set "_remote_dir=%~1"
set "_include=%~2"
set "_max=%MAX_FILE%"
if "%_max%"=="" set "_max=1"
echo [PREPARE] Enforce MAX_FILE=%_max% on %_remote_dir% include "%_include%"
"%RC%" ls "%_remote_dir%" --include "%_include%" | sort > "%TEMP%\_max_list.txt"
set /a _count=0
for /f "tokens=1,* delims= " %%S in ('type "%TEMP%\_max_list.txt"') do set /a _count+=1
if %_count% LEQ %_max% (
  echo [PREPARE] Không cần prune (count=%_count%)
  goto :eof
)
set /a _toMove=%_count% - %_max%
echo [PREPARE] Di chuyển %_toMove% bản cũ nhất vào 'old'
for /f "skip=%_max% tokens=1,* delims= " %%S in ('type "%TEMP%\_max_list.txt"') do (
  "%RC%" move "%%T" "%_remote_dir%/old/"
)
goto :eof

:: Bước 0: liệt kê A (ISO nguồn) và X (ISO đã build vietstar)
echo [PREPARE] List remote ISO nguồn
"%RC%" ls "%RCLONE_PATH%/%iso%/%folder%" --include "%patterns%" > "%TEMP%\_iso_src.txt"
echo [PREPARE] List remote ISO vietstar đã build
"%RC%" ls "%RCLONE_PATH%/%vietstar%/%folder%" --include "%patterns%" > "%TEMP%\_iso_vs.txt"

call :choose_latest_by_build "%TEMP%\_iso_src.txt" fileA
if "%fileA%"=="" call :choose_first_name "%TEMP%\_iso_src.txt" fileA

call :choose_latest_by_build "%TEMP%\_iso_vs.txt" fileX
if "%fileX%"=="" call :choose_first_name "%TEMP%\_iso_vs.txt" fileX

echo [PREPARE] fileA=%fileA%
echo [PREPARE] fileX=%fileX%

set "buildA="
set "buildX="
if not "%fileA%"=="" call :extract_build "%fileA%" buildA
if not "%fileX%"=="" call :extract_build "%fileX%" buildX

echo [PREPARE] buildA=%buildA% buildX=%buildX%

if not "%buildA%"=="" if not "%buildX%"=="" (
  if /I "%buildA%"=="%buildX%" (
    echo [PREPARE] Build code khớp → tạo skip flag và bỏ qua build
    > "%SCRIPT_PATH%\_skip_%MODE%.flag" echo SKIP
    goto :env_set
  ) else (
    echo [PREPARE] Build code khác nhau → enforce MAX_FILE và tiếp tục
    call :enforce_max "%RCLONE_PATH%/%vietstar%/%folder%" "%patterns%"
  )
) else (
  echo [PREPARE] Không trích được build code đầy đủ → tiếp tục build
)

:: Bước 1: tải file A/B/C/D
echo [PREPARE] Tải A vào %SCRIPT_PATH%\%iso%\%fileA%
aria2c -q -d "%SCRIPT_PATH%\%iso%" "%ALIST_PATH%/%iso%/%folder%/%fileA%"

:: chọn B (driver) theo mode
set "fileB="
if /I "%MODE%"=="7-32" "%RC%" ls "%RCLONE_PATH%/%driver%/DriverCeo/DP" --include "*7*86*.iso" > "%TEMP%\_drv.txt"
if /I "%MODE%"=="7-64" "%RC%" ls "%RCLONE_PATH%/%driver%/DriverCeo/DP" --include "*7*64*.iso" > "%TEMP%\_drv.txt"
if /I "%MODE%"=="10-32" "%RC%" ls "%RCLONE_PATH%/%driver%" --include "*Win10*x86*.iso" > "%TEMP%\_drv.txt"
if /I "%MODE%"=="10-64" "%RC%" ls "%RCLONE_PATH%/%driver%" --include "*Win10*x64*.iso" > "%TEMP%\_drv.txt"
if /I "%MODE%"=="11-64" "%RC%" ls "%RCLONE_PATH%/%driver%" --include "*Win10*x64*.iso" > "%TEMP%\_drv.txt"
if /I "%MODE%"=="11-64-ltsc" "%RC%" ls "%RCLONE_PATH%/%driver%" --include "*Win10*x64*.iso" > "%TEMP%\_drv.txt"
for /f "tokens=2" %%B in ('sort "%TEMP%\_drv.txt"') do set "fileB=%%~nxB"
if not "%fileB%"=="" (
  echo [PREPARE] Tải B: %fileB%
  if /I "%MODE:~0,2%"=="7-" (
    aria2c -q -d "%SCRIPT_PATH%\%driver%" "%ALIST_PATH%/%driver%/DriverCeo/DP/%fileB%"
  ) else (
    aria2c -q -d "%SCRIPT_PATH%\%driver%" "%ALIST_PATH%/%driver%/%fileB%"
  )
)

:: chọn C (boot) theo mode
set "fileC="
if /I "%MODE%"=="7-32" "%RC%" ls "%RCLONE_PATH%/%boot7%" --include "*7*86*.iso" > "%TEMP%\_boot.txt"
if /I "%MODE%"=="7-64" "%RC%" ls "%RCLONE_PATH%/%boot7%" --include "*7*64*.iso" > "%TEMP%\_boot.txt"
if /I "%MODE%"=="11-64" "%RC%" ls "%RCLONE_PATH%/%boot7%" --include "*11*64*.iso" > "%TEMP%\_boot.txt"
if /I "%MODE%"=="11-64-ltsc" "%RC%" ls "%RCLONE_PATH%/%boot7%" --include "*11*64*.iso" > "%TEMP%\_boot.txt"
for /f "tokens=2" %%C in ('sort "%TEMP%\_boot.txt"') do set "fileC=%%~nxC"
if not "%fileC%"=="" (
  echo [PREPARE] Tải C: %fileC%
  aria2c -q -d "%SCRIPT_PATH%\%boot7%" "%ALIST_PATH%/%boot7%/%fileC%"
)

:: chọn D (silent lite)
set "fileD="
"%RC%" ls "%RCLONE_PATH%/%silent%" --include "*lite*.iso" > "%TEMP%\_silent.txt"
for /f "tokens=2" %%D in ('sort "%TEMP%\_silent.txt"') do set "fileD=%%~nxD"
if not "%fileD%"=="" (
  echo [PREPARE] Tải D: %fileD%
  aria2c -q -d "%SCRIPT_PATH%\%silent%" "%ALIST_PATH%/%silent%/%fileD%"
)

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

:env_set
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
