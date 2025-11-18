@echo on
setlocal EnableExtensions EnableDelayedExpansion
chcp 1252 >nul

echo [DEBUG] prepare-build.cmd started
echo [DEBUG] MODE arg: "%~1"

set "MODE=%~1"
set "RC=%SCRIPT_PATH%\rclone.exe --config %SCRIPT_PATH%\rclone.conf %rclone_flag%"

if not exist "%SCRIPT_PATH%\rclone.exe" (
  echo [ERROR] rclone.exe not found at "%SCRIPT_PATH%\rclone.exe"
  exit /b 1
)
if not exist "%SCRIPT_PATH%\rclone.conf" (
  echo [ERROR] rclone.conf not found at "%SCRIPT_PATH%\rclone.conf"
  exit /b 1
)

echo [DEBUG] RCLONE_PATH=%RCLONE_PATH%
echo [DEBUG] ALIST_PATH=%ALIST_PATH%
echo [DEBUG] iso=%iso% driver=%driver% boot7=%boot7% silent=%silent% vietstar=%vietstar%

for %%D in ("%SCRIPT_PATH%\%iso%" "%SCRIPT_PATH%\%driver%" "%SCRIPT_PATH%\%boot7%" "%SCRIPT_PATH%\%silent%" "%SCRIPT_PATH%\%vietstar%") do (
  if not exist "%%~D" (
    echo [DEBUG] mkdir "%%~D"
    mkdir "%%~D"
  )
)

if not exist "%SCRIPT_PATH%\rule.env" (
  echo [ERROR] rule.env not found at "%SCRIPT_PATH%\rule.env"
  exit /b 1
)

set "folder="
set "patterns="
set "drvFolder="
set "drvPatterns="
set "bootFolder="
set "bootPatterns="
set "silentFolder="
set "silentPatterns="

for /f "usebackq tokens=1,* delims==" %%A in ("%SCRIPT_PATH%\rule.env") do (
  set "key=%%A"
  set "val=%%B"
  if /I "!key!"=="mode"          set "mode_rule=!val!"
  if /I "!key!"=="folder"        set "folder=!val!"
  if /I "!key!"=="patterns"      set "patterns=!val!"
  if /I "!key!"=="drvFolder"     set "drvFolder=!val!"
  if /I "!key!"=="drvPatterns"   set "drvPatterns=!val!"
  if /I "!key!"=="bootFolder"    set "bootFolder=!val!"
  if /I "!key!"=="bootPatterns"  set "bootPatterns=!val!"
  if /I "!key!"=="silentFolder"  set "silentFolder=!val!"
  if /I "!key!"=="silentPatterns" set "silentPatterns=!val!"
)

echo [DEBUG] mode_rule=%mode_rule%
echo [DEBUG] folder=%folder%
echo [DEBUG] patterns=%patterns%
echo [DEBUG] drvFolder=%drvFolder%
echo [DEBUG] drvPatterns=%drvPatterns%
echo [DEBUG] bootFolder=%bootFolder%
echo [DEBUG] bootPatterns=%bootPatterns%
echo [DEBUG] silentFolder=%silentFolder%
echo [DEBUG] silentPatterns=%silentPatterns%

set "TMP_LIST=%TEMP%\_rclone_ls.txt"

:choose_latest
set "_remote_dir=%~1"
set "_include=%~2"
set "_outvar=%~3"
if "%_include%"=="" (
  echo [DEBUG] choose_latest: include empty, skip
  goto :eof
)
echo [DEBUG] choose_latest: remote="%_remote_dir%" include="%_include%"
"%RC%" ls "%_remote_dir%" --include "%_include%" > "%TMP_LIST%" 2>&1
if errorlevel 1 (
  echo [ERROR] rclone ls failed on "%_remote_dir%" include "%_include%"
  type "%TMP_LIST%"
  del "%TMP_LIST%" >nul 2>&1
  goto :eof
)
for /f "usebackq tokens=1,* delims= " %%S in ("%TMP_LIST%") do (
  set "lastfile=%%~nxT"
)
set "%_outvar%=%lastfile%"
del "%TMP_LIST%" >nul 2>&1
goto :eof

:download_if_needed
set "_remote_dir=%~1"
set "_include=%~2"
set "_local_dir=%~3"
set "_file=%~4"
set "_alist_url=%~5"
if "%_file%"=="" (
  echo [DEBUG] download_if_needed: empty file, skip
  goto :eof
)
if not exist "%_local_dir%" mkdir "%_local_dir%"
set "_local_file=%_local_dir%\%_file%"
echo [DEBUG] download_if_needed: local="%_local_file%" remote="%_remote_dir%" include="%_include%" url="%_alist_url%"
if exist "%_local_file%" (
  for %%Z in ("%_local_file%") do set "_local_size=%%~zZ"
  echo [DEBUG] local_size=%_local_size%
)
echo [PREPARE] Download %_file%
aria2c -q -d "%_local_dir%" "%_alist_url%"
goto :eof

:: Bước 0: chọn file nguồn A và file build X
if not "%patterns%"=="" (
  call :choose_latest "%RCLONE_PATH%%iso%/%folder%" "%patterns%" fileA
  call :choose_latest "%RCLONE_PATH%%vietstar%/%folder%" "%patterns%" fileX
)

echo [DEBUG] fileA=%fileA%
echo [DEBUG] fileX=%fileX%

if /I "%fileA%"=="%fileX%" (
  echo [PREPARE] Same name A/X → set skip flag
  > "%SCRIPT_PATH%\_skip_%MODE%.flag" echo SKIP
  goto set_env
)

:: Bước 1: tải theo rule
if not "%fileA%"=="" (
  call :download_if_needed "%RCLONE_PATH%%iso%/%folder%" "%patterns%" "%SCRIPT_PATH%\%iso%" "%fileA%" "%ALIST_PATH%/%iso%/%folder%/%fileA%"
)

if not "%drvFolder%"=="" if not "%drvPatterns%"=="" (
  call :choose_latest "%RCLONE_PATH%%driver%/%drvFolder%" "%drvPatterns%" fileB
  call :download_if_needed "%RCLONE_PATH%%driver%/%drvFolder%" "%drvPatterns%" "%SCRIPT_PATH%\%driver%" "%fileB%" "%ALIST_PATH%/%driver%/%drvFolder%/%fileB%"
)

if not "%bootFolder%"=="" if not "%bootPatterns%"=="" (
  call :choose_latest "%RCLONE_PATH%%boot7%" "%bootPatterns%" fileC
  call :download_if_needed "%RCLONE_PATH%%boot7%" "%bootPatterns%" "%SCRIPT_PATH%\%boot7%" "%fileC%" "%ALIST_PATH%/%boot7%/%fileC%"
)

if not "%silentFolder%"=="" if not "%silentPatterns%"=="" (
  call :choose_latest "%RCLONE_PATH%%silent%" "%silentPatterns%" fileD
  call :download_if_needed "%RCLONE_PATH%%silent%" "%silentPatterns%" "%SCRIPT_PATH%\%silent%" "%fileD%" "%ALIST_PATH%/%silent%/%fileD%"
)

:: Bước 2: mount silent nếu có
if not "%fileD%"=="" (
  imdisk -D -m A: >nul 2>&1
  imdisk -a -m A: -f "%SCRIPT_PATH%\%silent%\%fileD%"
  if errorlevel 1 (
    echo [DEBUG] imdisk mount failed, fallback
    set "silent=%SCRIPT_PATH%\%silent%"
  ) else (
    set "silent=A:\Silent\VIETSTAR-Silent-Network\Apps\exe"
  )
) else (
  set "silent=%SCRIPT_PATH%\%silent%"
)

:set_env
set "vietstar=%SCRIPT_PATH%\%vietstar%"
set "oem=%SCRIPT_PATH%\%oem%"
set "dll=%SCRIPT_PATH%\%dll%"
set "driver=%SCRIPT_PATH%\%driver%"@echo on
setlocal EnableExtensions EnableDelayedExpansion
chcp 1252 >nul

echo [DEBUG] prepare-build.cmd started
echo [DEBUG] MODE arg: "%~1"

set "MODE=%~1"
set "RC=%SCRIPT_PATH%\rclone.exe --config %SCRIPT_PATH%\rclone.conf %rclone_flag%"

if not exist "%SCRIPT_PATH%\rclone.exe" (
  echo [ERROR] rclone.exe not found at "%SCRIPT_PATH%\rclone.exe"
  exit /b 1
)
if not exist "%SCRIPT_PATH%\rclone.conf" (
  echo [ERROR] rclone.conf not found at "%SCRIPT_PATH%\rclone.conf"
  exit /b 1
)

echo [DEBUG] RCLONE_PATH=%RCLONE_PATH%
echo [DEBUG] ALIST_PATH=%ALIST_PATH%
echo [DEBUG] iso=%iso% driver=%driver% boot7=%boot7% silent=%silent% vietstar=%vietstar%

for %%D in ("%SCRIPT_PATH%\%iso%" "%SCRIPT_PATH%\%driver%" "%SCRIPT_PATH%\%boot7%" "%SCRIPT_PATH%\%silent%" "%SCRIPT_PATH%\%vietstar%") do (
  if not exist "%%~D" (
    echo [DEBUG] mkdir "%%~D"
    mkdir "%%~D"
  )
)

if not exist "%SCRIPT_PATH%\rule.env" (
  echo [ERROR] rule.env not found at "%SCRIPT_PATH%\rule.env"
  exit /b 1
)

set "folder="
set "patterns="
set "drvFolder="
set "drvPatterns="
set "bootFolder="
set "bootPatterns="
set "silentFolder="
set "silentPatterns="

for /f "usebackq tokens=1,* delims==" %%A in ("%SCRIPT_PATH%\rule.env") do (
  set "key=%%A"
  set "val=%%B"
  if /I "!key!"=="mode"          set "mode_rule=!val!"
  if /I "!key!"=="folder"        set "folder=!val!"
  if /I "!key!"=="patterns"      set "patterns=!val!"
  if /I "!key!"=="drvFolder"     set "drvFolder=!val!"
  if /I "!key!"=="drvPatterns"   set "drvPatterns=!val!"
  if /I "!key!"=="bootFolder"    set "bootFolder=!val!"
  if /I "!key!"=="bootPatterns"  set "bootPatterns=!val!"
  if /I "!key!"=="silentFolder"  set "silentFolder=!val!"
  if /I "!key!"=="silentPatterns" set "silentPatterns=!val!"
)

echo [DEBUG] mode_rule=%mode_rule%
echo [DEBUG] folder=%folder%
echo [DEBUG] patterns=%patterns%
echo [DEBUG] drvFolder=%drvFolder%
echo [DEBUG] drvPatterns=%drvPatterns%
echo [DEBUG] bootFolder=%bootFolder%
echo [DEBUG] bootPatterns=%bootPatterns%
echo [DEBUG] silentFolder=%silentFolder%
echo [DEBUG] silentPatterns=%silentPatterns%

set "TMP_LIST=%TEMP%\_rclone_ls.txt"

:choose_latest
set "_remote_dir=%~1"
set "_include=%~2"
set "_outvar=%~3"
if "%_include%"=="" (
  echo [DEBUG] choose_latest: include empty, skip
  goto :eof
)
echo [DEBUG] choose_latest: remote="%_remote_dir%" include="%_include%"
"%RC%" ls "%_remote_dir%" --include "%_include%" > "%TMP_LIST%" 2>&1
if errorlevel 1 (
  echo [ERROR] rclone ls failed on "%_remote_dir%" include "%_include%"
  type "%TMP_LIST%"
  del "%TMP_LIST%" >nul 2>&1
  goto :eof
)
for /f "usebackq tokens=1,* delims= " %%S in ("%TMP_LIST%") do (
  set "lastfile=%%~nxT"
)
set "%_outvar%=%lastfile%"
del "%TMP_LIST%" >nul 2>&1
goto :eof

:download_if_needed
set "_remote_dir=%~1"
set "_include=%~2"
set "_local_dir=%~3"
set "_file=%~4"
set "_alist_url=%~5"
if "%_file%"=="" (
  echo [DEBUG] download_if_needed: empty file, skip
  goto :eof
)
if not exist "%_local_dir%" mkdir "%_local_dir%"
set "_local_file=%_local_dir%\%_file%"
echo [DEBUG] download_if_needed: local="%_local_file%" remote="%_remote_dir%" include="%_include%" url="%_alist_url%"
if exist "%_local_file%" (
  for %%Z in ("%_local_file%") do set "_local_size=%%~zZ"
  echo [DEBUG] local_size=%_local_size%
)
echo [PREPARE] Download %_file%
aria2c -q -d "%_local_dir%" "%_alist_url%"
goto :eof

:: Bước 0: chọn file nguồn A và file build X
if not "%patterns%"=="" (
  call :choose_latest "%RCLONE_PATH%%iso%/%folder%" "%patterns%" fileA
  call :choose_latest "%RCLONE_PATH%%vietstar%/%folder%" "%patterns%" fileX
)

echo [DEBUG] fileA=%fileA%
echo [DEBUG] fileX=%fileX%

if /I "%fileA%"=="%fileX%" (
  echo [PREPARE] Same name A/X → set skip flag
  > "%SCRIPT_PATH%\_skip_%MODE%.flag" echo SKIP
  goto set_env
)

:: Bước 1: tải theo rule
if not "%fileA%"=="" (
  call :download_if_needed "%RCLONE_PATH%%iso%/%folder%" "%patterns%" "%SCRIPT_PATH%\%iso%" "%fileA%" "%ALIST_PATH%/%iso%/%folder%/%fileA%"
)

if not "%drvFolder%"=="" if not "%drvPatterns%"=="" (
  call :choose_latest "%RCLONE_PATH%%driver%/%drvFolder%" "%drvPatterns%" fileB
  call :download_if_needed "%RCLONE_PATH%%driver%/%drvFolder%" "%drvPatterns%" "%SCRIPT_PATH%\%driver%" "%fileB%" "%ALIST_PATH%/%driver%/%drvFolder%/%fileB%"
)

if not "%bootFolder%"=="" if not "%bootPatterns%"=="" (
  call :choose_latest "%RCLONE_PATH%%boot7%" "%bootPatterns%" fileC
  call :download_if_needed "%RCLONE_PATH%%boot7%" "%bootPatterns%" "%SCRIPT_PATH%\%boot7%" "%fileC%" "%ALIST_PATH%/%boot7%/%fileC%"
)

if not "%silentFolder%"=="" if not "%silentPatterns%"=="" (
  call :choose_latest "%RCLONE_PATH%%silent%" "%silentPatterns%" fileD
  call :download_if_needed "%RCLONE_PATH%%silent%" "%silentPatterns%" "%SCRIPT_PATH%\%silent%" "%fileD%" "%ALIST_PATH%/%silent%/%fileD%"
)

:: Bước 2: mount silent nếu có
if not "%fileD%"=="" (
  imdisk -D -m A: >nul 2>&1
  imdisk -a -m A: -f "%SCRIPT_PATH%\%silent%\%fileD%"
  if errorlevel 1 (
    echo [DEBUG] imdisk mount failed, fallback
    set "silent=%SCRIPT_PATH%\%silent%"
  ) else (
    set "silent=A:\Silent\VIETSTAR-Silent-Network\Apps\exe"
  )
) else (
  set "silent=%SCRIPT_PATH%\%silent%"
)

:set_env
set "vietstar=%SCRIPT_PATH%\%vietstar%"
set "oem=%SCRIPT_PATH%\%oem%"
set "dll=%SCRIPT_PATH%\%dll%"
set "driver=%SCRIPT_PATH%\%driver%"
set "iso=%SCRIPT_PATH%\%iso%"
set "boot7=%SCRIPT_PATH%\%boot7%"
set "bootwim=%SCRIPT_PATH%\%bootwim%"

echo [PREPARE] Env OK
exit /b 0
