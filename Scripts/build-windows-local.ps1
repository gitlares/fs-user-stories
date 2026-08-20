# SPDX-License-Identifier: MIT
# Build the Windows x64 Qt application and its local NSIS installer.
# Prerequisites: Rust, CMake, Ninja, NSIS, Visual Studio Build Tools with the
# Desktop development with C++ workload, and Qt 6.7.3 for MSVC 64-bit.
# Set FS_USER_STORIES_QT_ROOT to the Qt kit directory when CMake cannot find it.

[CmdletBinding()]
param([switch]$SkipInstaller)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$coreDir = Join-Path $projectRoot 'Core'
$qtDir = Join-Path $projectRoot 'Platform\Qt'
$coreBundle = Join-Path $qtDir 'core-bundle'

foreach ($command in @('cargo', 'cmake', 'ninja')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Missing $command. See README.md > Build from source > Windows."
    }
}

$vsDevCmd = @(
    "$env:ProgramFiles\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat",
    "$env:ProgramFiles\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat",
    "$env:ProgramFiles\Microsoft Visual Studio\2022\Enterprise\Common7\Tools\VsDevCmd.bat"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $vsDevCmd) {
    throw 'Visual Studio 2022 Build Tools with Desktop development with C++ is required.'
}

Push-Location $projectRoot
try {
    $envCommand = "call `"$vsDevCmd`" -arch=amd64 -host_arch=amd64 && cargo build --manifest-path `"$coreDir\Cargo.toml`" --release --locked --target x86_64-pc-windows-msvc"
    & cmd.exe /d /s /c $envCommand
    if ($LASTEXITCODE -ne 0) { throw 'Rust core build failed.' }

    New-Item -ItemType Directory -Force -Path $coreBundle | Out-Null
    Copy-Item -Force "$coreDir\target\x86_64-pc-windows-msvc\release\fs-user-stories-core.exe" $coreBundle

    $cmakeArguments = @('-S', $qtDir, '-B', "$qtDir\build", '-G', 'Ninja', '-DCMAKE_BUILD_TYPE=Release')
    if ($env:FS_USER_STORIES_QT_ROOT) {
        $cmakeArguments += "-DCMAKE_PREFIX_PATH=$env:FS_USER_STORIES_QT_ROOT"
    }
    & cmake @cmakeArguments
    if ($LASTEXITCODE -ne 0) { throw 'Qt configuration failed. Set FS_USER_STORIES_QT_ROOT to the Qt MSVC kit.' }
    & cmake --build "$qtDir\build" --parallel
    if ($LASTEXITCODE -ne 0) { throw 'Qt application build failed.' }

    if (-not $SkipInstaller) {
        if (-not (Get-Command makensis -ErrorAction SilentlyContinue)) {
            throw 'NSIS is required to create the installer. Re-run with -SkipInstaller to build only the application.'
        }
        & "$PSScriptRoot\build-windows-app.ps1"
    }
} finally {
    Pop-Location
}
