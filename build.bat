@echo off
setlocal enabledelayedexpansion

REM 讀取版本
for /f "usebackq tokens=*" %%v in ("VERSION") do set APPVER=%%v

REM 同步 src\version.py 的 __version__
powershell -Command "(Get-Content src/version.py) -replace '__version__ = \"[^\"]+\"','__version__ = \"%APPVER%\"' | Set-Content src/version.py -Encoding UTF8"

REM 同步 version.rc 的 FileVersion/ProductVersion 與數字
for /f "tokens=1-3 delims=." %%a in ("%APPVER%") do (
  set V1=%%a
  set V2=%%b
  set V3=%%c
)
powershell -Command "(Get-Content version.rc) -replace 'filevers=\\([0-9, ]+\\)','filevers=(%V1%,%V2%,%V3%,0)' -replace 'prodvers=\\([0-9, ]+\\)','prodvers=(%V1%,%V2%,%V3%,0)' -replace 'FileVersion', 'FileVersion' -replace 'ProductVersion', 'ProductVersion' | Set-Content version.rc -Encoding UTF8"
powershell -Command "(Get-Content version.rc) -replace 'StringStruct\(''FileVersion'',[^)]*\)','StringStruct(''FileVersion'', ''%APPVER%'')' -replace 'StringStruct\(''ProductVersion'',[^)]*\)','StringStruct(''ProductVersion'', ''%APPVER%'')' | Set-Content version.rc -Encoding UTF8"

REM 清理舊輸出
if exist build rd /s /q build
if exist dist rd /s /q dist

REM 打包（方案B：onedir）
pyinstaller --onedir --name l50-bridge --version-file=version.rc src/main.py

REM 複製 config.json 到輸出資料夾
if exist config.json copy /Y config.json dist\l50-bridge\

echo.
echo Build done. Output: dist\l50-bridge\
echo Version: %APPVER%

