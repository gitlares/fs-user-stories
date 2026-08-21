#!/bin/sh
# Builds the FS User Stories Qt front-end and bundles an AppImage.
#
# Requirements (Ubuntu/Debian):
#   apt install build-essential cmake ninja-build pkg-config \
#               qt6-base-dev qt6-declarative-dev qt6-tools-dev \
#               qt6-quickcontrols2-6-dev libqt6quick6 libqt6quickcontrols2-6
#   cargo install --locked cargo-bundle  # optional
#   wget https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage \
#        -O /usr/local/bin/linuxdeploy
#   wget https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage \
#        -O /usr/local/bin/linuxdeploy-plugin-qt
#   chmod +x /usr/local/bin/linuxdeploy*

set -eu

SCRIPT_DIRECTORY=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIRECTORY=$(dirname "$SCRIPT_DIRECTORY")
QT_PROJECT="$PROJECT_DIRECTORY/Platform/Qt"
BUILD_DIRECTORY="$QT_PROJECT/build"
APP_DIR="$BUILD_DIRECTORY/AppDir"
OUTPUT_DIR="$PROJECT_DIRECTORY/Distribution/Linux"
APP_NAME="FSUserStories"
APP_VERSION="1.0.8"

if ! command -v cmake >/dev/null 2>&1; then
    echo "cmake is required" >&2
    exit 1
fi

if ! command -v qmake6 >/dev/null 2>&1 && ! command -v qmake-qt6 >/dev/null 2>&1; then
    echo "Qt 6 development tools are required (qmake6)" >&2
    exit 1
fi

# 1. Build the Rust core for the running Linux target.
"$(dirname "$0")/build-core-linux.sh"

# 2. Configure & build the Qt app.
cmake -S "$QT_PROJECT" -B "$BUILD_DIRECTORY" -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD_DIRECTORY" --parallel

# 3. Build the AppDir layout.
mkdir -p "$APP_DIR/usr/bin"
mkdir -p "$APP_DIR/usr/lib/fs-user-stories/core"
mkdir -p "$APP_DIR/usr/share/applications"
mkdir -p "$APP_DIR/usr/share/icons/hicolor/256x256/apps"

cp "$BUILD_DIRECTORY/fs-user-stories" "$APP_DIR/usr/bin/fs-user-stories"
cp "$QT_PROJECT/core-bundle/fs-user-stories-core" \
    "$APP_DIR/usr/lib/fs-user-stories/core/fs-user-stories-core"
cp "$QT_PROJECT/resources/fs-user-stories.desktop" \
    "$APP_DIR/usr/share/applications/fs-user-stories.desktop"

# Bundle the Material Symbols icon font next to the binary so main.cpp can
# QFontDatabase::addApplicationFont(applicationDirPath() + "/resources/fonts/...").
if [ -d "$BUILD_DIRECTORY/resources/fonts" ]; then
    mkdir -p "$APP_DIR/usr/bin/resources/fonts"
    cp -r "$BUILD_DIRECTORY/resources/fonts/"*.ttf \
          "$APP_DIR/usr/bin/resources/fonts/" 2>/dev/null || true
fi

# Use the master icon if available, otherwise fall back to a placeholder.
if [ -f "$PROJECT_DIRECTORY/Design/AppIcon-master.png" ]; then
    cp "$PROJECT_DIRECTORY/Design/AppIcon-master.png" \
       "$APP_DIR/usr/share/icons/hicolor/256x256/apps/fs-user-stories.png"
    # Resize to 256x256 if the source has a different resolution (linuxdeploy
    # rejects icons whose dimensions do not match the directory hint).
    if command -v convert >/dev/null 2>&1; then
        convert "$APP_DIR/usr/share/icons/hicolor/256x256/apps/fs-user-stories.png" \
                -resize 256x256 \
                "$APP_DIR/usr/share/icons/hicolor/256x256/apps/fs-user-stories.png"
    elif command -v magick >/dev/null 2>&1; then
        magick "$APP_DIR/usr/share/icons/hicolor/256x256/apps/fs-user-stories.png" \
               -resize 256x256 \
               "$APP_DIR/usr/share/icons/hicolor/256x256/apps/fs-user-stories.png"
    fi
fi

# 4. Wrap into an AppImage using linuxdeploy.
export QML_SOURCES_PATHS="$QT_PROJECT/src/qml"
linuxdeploy --appdir "$APP_DIR" \
    --desktop-file "$APP_DIR/usr/share/applications/fs-user-stories.desktop" \
    --icon-file "$APP_DIR/usr/share/icons/hicolor/256x256/apps/fs-user-stories.png" \
    --plugin qt \
    --output appimage \
    --custom-apprun "$QT_PROJECT/scripts/AppRun" 2>/dev/null || \
linuxdeploy --appdir "$APP_DIR" \
    --desktop-file "$APP_DIR/usr/share/applications/fs-user-stories.desktop" \
    --icon-file "$APP_DIR/usr/share/icons/hicolor/256x256/apps/fs-user-stories.png" \
    --plugin qt \
    --output appimage

mkdir -p "$OUTPUT_DIR"
mv "$BUILD_DIRECTORY"/*.AppImage "$OUTPUT_DIR/" 2>/dev/null || true
echo "AppImage written to $OUTPUT_DIR"
