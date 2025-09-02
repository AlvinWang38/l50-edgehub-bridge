@echo off
setlocal enabledelayedexpansion

REM ===== 基本資訊 =====
set APPNAME=l50-edgehub-bridge

REM 讀 VERSION 檔做為版本號
for /f "usebackq tokens=*" %%v in ("VERSION") do set APPVER=%%v

echo Building %APPNAME% %APPVER% (onefile)...

REM 同步 src\version.py 的 __version__
powershell -Command "(Get-Content src/version.py) -replace '__version__ = \"[^\"]+\"','__version__ = \"%APPVER%\"' | Set-Content src/version.py -Encoding UTF8"

REM 同步 version.rc 的版本
for /f "tokens=1-3 delims=." %%a in ("%APPVER%") do ( set V1=%%a & set V2=%%b & set V3=%%c )
powershell -Command "(Get-Content version.rc) -replace 'filevers=\\([0-9, ]+\\)','filevers=(%V1%,%V2%,%V3%,0)' -replace 'prodvers=\\([0-9, ]+\\)','prodvers=(%V1%,%V2%,%V3%,0)' | Set-Content version.rc -Encoding UTF8"
powershell -Command "(Get-Content version.rc) -replace 'StringStruct\(''FileVersion'',[^)]*\)','StringStruct(''FileVersion'', ''%APPVER%'')' -replace 'StringStruct\(''ProductVersion'',[^)]*\)','StringStruct(''ProductVersion'', ''%APPVER%'')' | Set-Content version.rc -Encoding UTF8"

REM 清理上一版輸出
if exist build rd /s /q build
if exist dist rd /s /q dist

REM ===== 打包（onefile）=====
pyinstaller --onefile --name %APPNAME%-%APPVER% --version-file=version.rc src/main.py
if errorlevel 1 ( echo PyInstaller failed & exit /b 1 )

REM 建立帶版本資料夾，並搬移成品與 config.json
set OUTDIR=dist\%APPNAME%-%APPVER%
if not exist "%OUTDIR%" mkdir "%OUTDIR%"
move /Y "dist\%APPNAME%-%APPVER%.exe" "%OUTDIR%\"
if exist config.json copy /Y config.json "%OUTDIR%\"

REM 產生 SHA256 供驗證（可選）
powershell -Command "Get-FileHash '%OUTDIR%\%APPNAME%-%APPVER%.exe' -Algorithm SHA256 | ForEach-Object { $_.Hash } > '%OUTDIR%\%APPNAME%-%APPVER%.sha256'"

echo.
echo Build done:
echo   %OUTDIR%\%APPNAME%-%APPVER%.exe
echo   %OUTDIR%\config.json
echo.

