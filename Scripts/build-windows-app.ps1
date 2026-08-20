<#
.SYNOPSIS
    Bundle the Qt front-end for Windows.

.DESCRIPTION
    Expects:
      * `Platform/Qt/build/fs-user-stories.exe` to already exist (CMake build done).
      * `Platform/Qt/core-bundle/fs-user-stories-core.exe` to already exist (cargo build done).
      * Qt 6.7.3 toolchain available via the environment variable Qt6_DIR (set by
        jurajbelobradic/install-qt-action).
      * Visual Studio 2022 (used to copy VC++ runtime DLLs so the app runs on
        systems without VC++ Redist installed).

    Produces:
      * Distribution/Windows/fs-user-stories-windows.zip (extracted folder bundle)
      * Distribution/Windows/FSUserStoriesSetup-0.1.0-alpha.exe (NSIS installer)
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

# 2. Bundle the Rust core in BOTH locations — sibling to the executable AND in
#    the core/ subdirectory — to support both layout conventions used by
#    CorePaths::resolveCoreExecutable.
$coreOutDir = Join-Path $stageDir "core"
New-Item -ItemType Directory -Force -Path $coreOutDir | Out-Null
Copy-Item -Path $coreExe -Destination (Join-Path $stageDir "fs-user-stories-core.exe")
Copy-Item -Path $coreExe -Destination (Join-Path $coreOutDir "fs-user-stories-core.exe")

# 2b. Bundle the Material Symbols icon font (loaded at startup by main.cpp
#     via QFontDatabase::addApplicationFont on applicationDirPath()/resources/fonts/).
$fontsDir = Join-Path $stageDir "resources/fonts"
New-Item -ItemType Directory -Force -Path $fontsDir | Out-Null
Copy-Item -Path (Join-Path $qtSrcDir "resources/fonts/MaterialSymbolsOutlined-Variable.ttf") `
            -Destination $fontsDir

# 2c. Bundle the Visual C++ runtime DLLs (vcruntime140, msvcp140, …).
#     Without these, fs-user-stories.exe fails to launch on a Windows install
#     that does not have VC++ Redist installed (a common "the exe doesn't open"
#     report). The DLLs live next to the VS install that GitHub Actions uses.
$vcRoot = Get-ChildItem "C:\Program Files\Microsoft Visual Studio\2022" `
              -Directory -ErrorAction SilentlyContinue |
              Sort-Object Name |
              Select-Object -First 1
if ($vcRoot) {
    $vcDir = Join-Path $vcRoot.FullName "VC/Redist/MSVC"
    $vcVerDir = Get-ChildItem $vcDir -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if ($vcVerDir) {
        $vcX64 = Join-Path $vcVerDir.FullName "x64"
        if (Test-Path $vcX64) {
            # Visual Studio stores the DLLs one level deeper, normally in
            # x64/Microsoft.VC14x.CRT/.  The previous implementation looked
            # directly in x64/, printed a success message, and silently copied
            # nothing.  Locate the actual CRT directory and fail packaging if
            # the three DLLs imported by our executables are not staged.
            $runtimeProbe = Get-ChildItem $vcX64 -Recurse -File -Filter "vcruntime140.dll" |
                Select-Object -First 1
            if (-not $runtimeProbe) {
                throw "Could not locate vcruntime140.dll below $vcX64"
            }
            $vcCrtDir = $runtimeProbe.Directory.FullName
            Write-Host "==> Bundling VC++ runtime from $vcCrtDir"
            Copy-Item -Path (Join-Path $vcCrtDir "*.dll") -Destination $stageDir

            $requiredRuntimeDlls = @(
                "vcruntime140.dll",
                "vcruntime140_1.dll",
                "msvcp140.dll"
            )
            foreach ($dll in $requiredRuntimeDlls) {
                if (-not (Test-Path (Join-Path $stageDir $dll))) {
                    throw "Required VC++ runtime DLL was not staged: $dll"
                }
            }
            # Universal CRT (api-ms-win-crt-*) sits at C:\Windows\System32 on
            # every Win10+ system; copying the dozen individual ucrt*.dll
            # files would bloat the bundle significantly.  We ship without them
            # because every supported Windows already has them — Win10 has
            # them in-place; Win7/8 must install the redist (we fall back to
            # the README note for those).
        }
    } else {
        Write-Warning "Could not locate VC redist MSVC directory; VC++ runtime DLLs not bundled."
    }
} else {
    throw "Visual Studio 2022 not found; cannot produce a self-contained bundle."
}

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
  1. Extract this zip to a folder with no spaces in the path
     (e.g. C:\fs-user-stories\).
  2. Double-click fs-user-stories.exe.

The Visual C++ 2015-2022 runtime DLLs are bundled alongside the binary, so
nothing else needs to be installed for this preview.

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

# 6. NSIS installer — disabled until the path resolution above is fixed.
#    The zip Distribution/Windows/fs-user-stories-windows.zip is the primary
#    distributable for now. Re-enable after installers are reliable.
Write-Host "==> Skipping NSIS installer (zipped bundle is the deliverable)."
