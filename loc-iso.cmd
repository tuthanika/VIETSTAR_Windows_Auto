@echo off
setlocal enabledelayedexpansion

rem === Nhận tham số chế độ build ===
set "mode=%~1"

rem === Tra pattern theo mode từ biến môi trường hoặc fallback từ file ===
set "pattern="
if not "%MODE_PATTERNS%"=="" (
    for /f "tokens=1,* delims==" %%a in ('echo %MODE_PATTERNS% ^| findstr /i "^%mode%="') do (
        set "pattern=%%b"
    )
) else (
    for /f "tokens=1,* delims==" %%a in ('type "%SCRIPT_PATH%\patterns.txt" ^| findstr /i "^%mode%="') do (
        set "pattern=%%b"
    )
)

if not defined pattern (
    echo [ERROR] Không tìm thấy pattern cho chế độ %mode%
    exit /b 1
)

rem === Kiểm tra file ISO trong vietstar theo pattern ===
set "found=0"
for %%f in ("%vietstar%\%pattern%") do (
    set "found=1"

    rem === Di chuyển file cũ trong OK_UPLOAD vào old ===
    for %%x in ("%OK_UPLOAD%\%pattern%") do (
        if not exist "%OK_UPLOAD%\old" mkdir "%OK_UPLOAD%\old"
        echo [INFO] Di chuyển %%~nxx từ OK_UPLOAD vào old
        move /Y "%%x" "%OK_UPLOAD%\old\"
    )

    rem === Lọc và xóa bản cũ nhất trong old nếu vượt quá OLD_LIMIT ===
    set "count=0"
    for /f %%i in ('dir /b /a:-d /o:d "%OK_UPLOAD%\old\%pattern%" 2^>nul') do (
        set /a count+=1
        set "file[!count!]=%%i"
    )

    if !count! GTR %OLD_LIMIT% (
        set /a excess=!count! - %OLD_LIMIT%
        for /L %%j in (1,1,!excess!) do (
            echo [INFO] Xóa bản cũ: !file[%%j]!
            rclone delete "%REMOTE_NAME%:%REMOTE_TARGET%/old/!file[%%j]!" %rclone_flag% --config "%RCLONE_CONFIG_PATH%"
        )
    )

    rem === Upload file mới bằng rclone copy ===
    echo [INFO] Upload %%~nxf từ vietstar lên remote
    rclone copy "%%f" "%REMOTE_NAME%:%REMOTE_TARGET%" --progress %rclone_flag% --config "%RCLONE_CONFIG_PATH%"
)

if "!found!"=="0" (
    echo [ERROR] Không tìm thấy file ISO trong %vietstar% theo pattern %pattern%
    exit /b 1
)

endlocal
