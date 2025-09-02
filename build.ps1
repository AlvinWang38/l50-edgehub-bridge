$ErrorActionPreference = "Stop"

# ===== 讀取版本與名稱 =====
$APPNAME = "l50-edgehub-bridge"
$APPVER  = (Get-Content -Raw -Encoding UTF8 -Path "VERSION").Trim()

Write-Host "Building $APPNAME $APPVER (onefile)..." -ForegroundColor Cyan

# 同步 src\version.py 的 __version__
(Get-Content -Raw -Encoding UTF8 "src/version.py") `
  -replace '__version__ = "[^"]+"', "__version__ = `"$APPVER`"" |
  Set-Content -Encoding UTF8 "src/version.py"

# 同步 version.rc 的數字與字串版本
$rc = Get-Content -Raw -Encoding UTF8 "version.rc"
$nums = $APPVER.Split(".")
$rc = $rc `
  -replace 'filevers=\([0-9, ]+\)', ("filevers=({0},{1},{2},0)" -f $nums[0],$nums[1],$nums[2]) `
  -replace 'prodvers=\([0-9, ]+\)', ("prodvers=({0},{1},{2},0)" -f $nums[0],$nums[1],$nums[2]) `
  -replace "StringStruct\('FileVersion',[^)]*\)", ("StringStruct('FileVersion', '{0}')" -f $APPVER) `
  -replace "StringStruct\('ProductVersion',[^)]*\)", ("StringStruct('ProductVersion', '{0}')" -f $APPVER)
Set-Content -Encoding UTF8 "version.rc" $rc

# 清乾淨舊輸出
if (Test-Path build) { Remove-Item -Recurse -Force build }
if (Test-Path dist)  { Remove-Item -Recurse -Force dist  }

# 確保 pyinstaller 可用
python -m pip show pyinstaller | Out-Null 2>$null
if ($LASTEXITCODE -ne 0) {
  Write-Host "Installing pyinstaller..." -ForegroundColor Yellow
  python -m pip install pyinstaller
}

# ===== 打包：onefile =====
$exeName = "$APPNAME-$APPVER.exe"
python -m PyInstaller --onefile --name "$APPNAME-$APPVER" --version-file=version.rc src/main.py

# 建置結果移到帶版本資料夾，並複製 config.json
$outDir = Join-Path "dist" "$APPNAME-$APPVER"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Move-Item -Force (Join-Path "dist" $exeName) (Join-Path $outDir $exeName)

if (Test-Path "config.json") {
  Copy-Item -Force "config.json" $outDir
}

# 產生 SHA256（可選）
Get-FileHash (Join-Path $outDir $exeName) -Algorithm SHA256 |
  Select-Object -ExpandProperty Hash |
  Out-File -Encoding ascii (Join-Path $outDir "$APPNAME-$APPVER.sha256")

Write-Host ""
Write-Host "Build done:" -ForegroundColor Green
Write-Host "  $outDir\$exeName"
Write-Host "  $outDir\config.json"

