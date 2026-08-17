<#
.SYNOPSIS
    Bundle the Qt front-end for Windows.

.DESCRIPTION
    Expects:
      * `Platform/Qt/build/fs-user-stories.exe` to already exist (CMake build done).
      * `Platform/Qt/core-bundle/fs-user-stories-core.exe` to already exist (cargo build done).
      * Qt 6.7.3 toolchain available via the environment variable Qt6_DIR (set by
        jurajbelobradic/install-qt-action).

    Produces Distribution/Windows/fs-user-stories-windows.zip ready for sharing.
#>

$ErrorActionPreference = "Stop"

$projectRoot = Resolve-Path "$PSScriptRoot/.."
$qtBuildDir  = Join-Path $projectRoot "Platform/Qt/build"
$qtSrcDir    = Join-Path $projectRoot "Platform/Qt"
$coreExe     = Join-Path $qtSrcDir "core-bundle/fs-user-stories-core.exe"
$exePath     = Join-Path $qtBuildDir "fs-user-stories.exe"

if (-not (Test-Path $exePath)) { throw "Missing $exePath — build with cmake first." }
if (-not (Test-Path $coreExe)) { throw "Missing $coreExe — build the Rust core for windows first." }

$outRoot  = Join-Path $projectRoot "Distribution/Windows"
$stageDir = Join-Path $outRoot "fs-user-stories"
if (Test-Path $stageDir) { Remove-Item -Recurse -Force $stageDir }
New-Item -ItemType Directory -Force -Path $stageDir | Out-Null

# 1. Copy the binary.
Copy-Item -Path $exePath -Destination (Join-Path $stageDir "fs-user-stories.exe")

# 2. Bundle the Rust core next to the binary.
$coreOutDir = Join-Path $stageDir "core"
New-Item -ItemType Directory -Force -Path $coreOutDir | Out-Null
Copy-Item -Path $coreExe -Destination (Join-Path $coreOutDir "fs-user-stories-core.exe")

# 3. Run windeployqt — installs Qt runtime DLLs, QML modules, platform plugins.
$env:Qt6_DIR = $env:Qt6_DIR
$windeployqt = Join-Path $env:Qt6_DIR "bin/windeployqt.exe"
if (-not (Test-Path $windeployqt)) {
    throw "windeployqt not found at $windeployqt — is Qt6_DIR set?"
}
Write-Host "==> Running $windeployqt"
& $windeployqt --release --qmldir (Join-Path $qtSrcDir "src/qml") --no-translations `
    --no-system-d3d-compiler --no-opengl-sw (Join-Path $stageDir "fs-user-stories.exe")
if ($LASTEXITCODE -ne 0) { throw "windeployqt failed" }

# 4. Optional: bundle a placeholder .desktop-style shortcut. Windows uses .lnk
#    instead; we ship a README with usage instructions so testers know how to
#    launch.
$readme = @"
FS User Stories — Windows preview build

How to run:
  1. Extract this zip to a folder with no spaces in the path (e.g. C:\Users\you\fs-user-stories\).
  2. Double-click fs-user-stories.exe.

Data location (first run will create):
  %LOCALAPPDATA%\fs-user-stories\fs-user-stories\
"@
$readmePath = Join-Path $stageDir "README.txt"
Set-Content -Path $readmePath -Value $readme -Encoding UTF8

# 5. Zip up the staged directory.
$zipPath = Join-Path $outRoot "fs-user-stories-windows.zip"
if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
Compress-Archive -Path $stageDir -DestinationPath $zipPath -CompressionLevel Optimal
Write-Host "==> Created $zipPath"
Get-Item $zipPath | Select-Object FullName, Length
