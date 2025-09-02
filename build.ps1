$ErrorActionPreference = "Stop"

# ===== App name & version =====
$APPNAME = "l50-edgehub-bridge"
$APPVER  = (Get-Content -Raw -Encoding UTF8 -Path "VERSION").Trim()

Write-Host "Building $APPNAME $APPVER (onefile)..." -ForegroundColor Cyan

# Sync src\version.py
(Get-Content -Raw -Encoding UTF8 "src/version.py") `
  -replace '__version__ = "[^"]+"', "__version__ = `"$APPVER`"" |
  Set-Content -Encoding UTF8 "src/version.py"

# Sync version.rc numbers and strings
$rc = Get-Content -Raw -Encoding UTF8 "version.rc"
$nums = $APPVER.Split(".")
$rc = $rc `
  -replace 'filevers=\([0-9, ]+\)', ("filevers=({0},{1},{2},0)" -f $nums[0],$nums[1],$nums[2]) `
  -replace 'prodvers=\([0-9, ]+\)', ("prodvers=({0},{1},{2},0)" -f $nums[0],$nums[1],$nums[2]) `
  -replace "StringStruct\('FileVersion',[^)]*\)", ("StringStruct('FileVersion', '{0}')" -f $APPVER) `
  -replace "StringStruct\('ProductVersion',[^)]*\)", ("StringStruct('ProductVersion', '{0}')" -f $APPVER)
Set-Content -Encoding UTF8 "version.rc" $rc

# Stop any running old exe (avoid file lock)
Write-Host "Stopping any running $APPNAME* processes..." -ForegroundColor Yellow
Get-Process "$APPNAME*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300

# Clean outputs
if (Test-Path build) { Remove-Item -Recurse -Force build }
if (Test-Path dist)  { Remove-Item -Recurse -Force dist  }

# Ensure PyInstaller
python -m pip show pyinstaller | Out-Null 2>$null
if ($LASTEXITCODE -ne 0) {
  Write-Host "Installing pyinstaller..." -ForegroundColor Yellow
  python -m pip install pyinstaller
}

# ===== Build onefile exe =====
$exeName = "$APPNAME-$APPVER.exe"
python -m PyInstaller --onefile --name "$APPNAME-$APPVER" --version-file=version.rc src/main.py

# Arrange output folder and copy config.json
$outDir = Join-Path "dist" "$APPNAME-$APPVER"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Move-Item -Force (Join-Path "dist" $exeName) (Join-Path $outDir $exeName)

if (Test-Path "config.json") {
  Copy-Item -Force "config.json" $outDir
}

# Generate SHA256 (optional)
Get-FileHash (Join-Path $outDir $exeName) -Algorithm SHA256 |
  Select-Object -ExpandProperty Hash |
  Out-File -Encoding ascii (Join-Path $outDir "$APPNAME-$APPVER.sha256")

# ===== Release notes (EN) =====
$notesFile = Join-Path $outDir "RELEASE-NOTES.txt"
$now = Get-Date -Format "yyyy-MM-dd HH:mm"
$entry = @"
v$APPVER  ($now)
- Added release notes feature
- Build output packaged as ZIP

"@

if (Test-Path $notesFile) {
  Add-Content -Encoding utf8 $notesFile $entry
} else {
  @"
v0.0.1
- Initial version

v0.1.1
- Packaged as single executable (onefile)

$entry
"@ | Out-File -Encoding utf8 $notesFile
}

# ===== Zip the whole release folder =====
$zipPath = "dist\$APPNAME-$APPVER.zip"
if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
Compress-Archive -Path "$outDir\*" -DestinationPath $zipPath -Force

Write-Host ""
Write-Host "Build done:" -ForegroundColor Green
Write-Host "  $outDir\$exeName"
Write-Host "  $outDir\config.json"
Write-Host "  $outDir\RELEASE-NOTES.txt"
Write-Host "  $zipPath"
