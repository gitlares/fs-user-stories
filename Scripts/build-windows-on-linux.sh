#!/bin/sh
# Cross-build and smoke-test the Windows x64 bundle from an x86_64 Linux host.
# Qt host tools must be native Linux binaries; Qt target libraries are MinGW.

set -eu

SCRIPT_DIRECTORY=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIRECTORY=$(dirname "$SCRIPT_DIRECTORY")
QT_PROJECT="$PROJECT_DIRECTORY/Platform/Qt"
BUILD_DIRECTORY="$QT_PROJECT/build-windows-mingw"
CORE_BUNDLE="$QT_PROJECT/core-bundle/fs-user-stories-core.exe"
OUTPUT_DIRECTORY="$PROJECT_DIRECTORY/Distribution/Windows-MinGW"
STAGE_DIRECTORY="$OUTPUT_DIRECTORY/fs-user-stories"
QT_VERSION=${QT_VERSION:-6.7.3}
QT_HOST_ROOT=${QT_HOST_ROOT:-$PROJECT_DIRECTORY/.qt-host}
QT_TARGET_ROOT=${QT_TARGET_ROOT:-$PROJECT_DIRECTORY/.qt-target}
QT_HOST_PATH=${QT_HOST_PATH:-$QT_HOST_ROOT/$QT_VERSION/gcc_64}
QT_TARGET_PATH=${QT_TARGET_PATH:-$QT_TARGET_ROOT/$QT_VERSION/mingw_64}
RUST_TARGET=${RUST_TARGET:-x86_64-pc-windows-gnu}

for command in cmake ninja cargo rustup x86_64-w64-mingw32-g++ wine python3 zip; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Missing required command: $command" >&2
        exit 1
    fi
done

if [ ! -f "$QT_HOST_PATH/lib/cmake/Qt6/Qt6Config.cmake" ]; then
    python3 -m aqt install-qt linux desktop "$QT_VERSION" gcc_64 \
        -O "$QT_HOST_ROOT"
fi
if [ ! -f "$QT_TARGET_PATH/lib/cmake/Qt6/Qt6Config.cmake" ]; then
    python3 -m aqt install-qt windows desktop "$QT_VERSION" win64_mingw \
        -O "$QT_TARGET_ROOT"
fi

rustup target add "$RUST_TARGET"
cargo build \
    --manifest-path "$PROJECT_DIRECTORY/Core/Cargo.toml" \
    --release \
    --locked \
    --target "$RUST_TARGET"

mkdir -p "$(dirname "$CORE_BUNDLE")"
cp "$PROJECT_DIRECTORY/Core/target/$RUST_TARGET/release/fs-user-stories-core.exe" \
    "$CORE_BUNDLE"

cmake -S "$QT_PROJECT" -B "$BUILD_DIRECTORY" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$QT_PROJECT/cmake/mingw-x86_64.cmake" \
    -DCMAKE_PREFIX_PATH="$QT_TARGET_PATH" \
    -DQT_HOST_PATH="$QT_HOST_PATH"
cmake --build "$BUILD_DIRECTORY" --parallel

rm -rf "$STAGE_DIRECTORY"
mkdir -p "$STAGE_DIRECTORY/core" "$STAGE_DIRECTORY/resources/fonts"
cp "$BUILD_DIRECTORY/fs-user-stories.exe" "$STAGE_DIRECTORY/"
cp "$CORE_BUNDLE" "$STAGE_DIRECTORY/"
cp "$CORE_BUNDLE" "$STAGE_DIRECTORY/core/"
cp "$QT_PROJECT/resources/fonts/MaterialSymbolsOutlined-Variable.ttf" \
    "$STAGE_DIRECTORY/resources/fonts/"

# windeployqt is a Windows target tool, so run it under Wine. It determines
# the Qt/QML plugin closure from the freshly built executable.
wine "$QT_TARGET_PATH/bin/windeployqt.exe" \
    --release \
    --qmldir "Z:$QT_PROJECT/src/qml" \
    --no-translations \
    "Z:$STAGE_DIRECTORY/fs-user-stories.exe"

# Deploy the exact MinGW runtime used by the compiler, then fail if any lookup
# unexpectedly resolves to a bare filename instead of a real DLL.
for runtime in libgcc_s_seh-1.dll libstdc++-6.dll libwinpthread-1.dll; do
    runtime_path=$(x86_64-w64-mingw32-g++ -print-file-name="$runtime")
    if [ ! -f "$runtime_path" ]; then
        echo "Could not resolve MinGW runtime: $runtime" >&2
        exit 1
    fi
    cp "$runtime_path" "$STAGE_DIRECTORY/"
done

# Launch the final staged bundle before publishing it. Xvfb supplies the
# display Wine needs while --smoke-test exits after loading QML and the core.
if command -v xvfb-run >/dev/null 2>&1; then
    xvfb-run -a wine "$STAGE_DIRECTORY/fs-user-stories.exe" --smoke-test
else
    wine "$STAGE_DIRECTORY/fs-user-stories.exe" --smoke-test
fi

mkdir -p "$OUTPUT_DIRECTORY"
rm -f "$OUTPUT_DIRECTORY/fs-user-stories-windows-mingw.zip"
(
    cd "$OUTPUT_DIRECTORY"
    zip -qr fs-user-stories-windows-mingw.zip fs-user-stories
)
echo "Created $OUTPUT_DIRECTORY/fs-user-stories-windows-mingw.zip"
