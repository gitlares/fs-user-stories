#!/bin/sh
# Builds the FS User Stories Qt front-end and bundles an AppImage.
#
# Requirements (Ubuntu/Debian):
#   apt install build-essential cmake ninja-build pkg-config libsecret-1-dev
#   Install a Qt 6.5+ desktop kit, then set FS_USER_STORIES_QT_ROOT to it.
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
APPIMAGE_OUTPUT="$OUTPUT_DIR/$APP_NAME-$APP_VERSION-x86_64.AppImage"

if ! command -v cmake >/dev/null 2>&1; then
    echo "cmake is required" >&2
    exit 1
fi

if ! command -v linuxdeploy >/dev/null 2>&1 || \
   ! command -v linuxdeploy-plugin-qt >/dev/null 2>&1; then
    echo "linuxdeploy and linuxdeploy-plugin-qt are required" >&2
    exit 1
fi

QT_ROOT=${FS_USER_STORIES_QT_ROOT:-}
if [ -n "$QT_ROOT" ]; then
    if [ ! -f "$QT_ROOT/lib/cmake/Qt6/Qt6Config.cmake" ]; then
        echo "FS_USER_STORIES_QT_ROOT does not point to a Qt desktop kit: $QT_ROOT" >&2
        exit 1
    fi
elif ! command -v qmake6 >/dev/null 2>&1 && \
     ! command -v qmake-qt6 >/dev/null 2>&1; then
    echo "Qt 6.5+ is required. Set FS_USER_STORIES_QT_ROOT to its desktop kit." >&2
    exit 1
fi

# 1. Build the Rust core for the running Linux target.
FS_USER_STORIES_TARGET=${FS_USER_STORIES_TARGET:-x86_64-unknown-linux-gnu}
export FS_USER_STORIES_TARGET
"$(dirname "$0")/build-core-linux.sh"

# 2. Configure & build the Qt app.
if [ -n "$QT_ROOT" ]; then
    cmake -S "$QT_PROJECT" -B "$BUILD_DIRECTORY" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$QT_ROOT"
else
    cmake -S "$QT_PROJECT" -B "$BUILD_DIRECTORY" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release
fi
cmake --build "$BUILD_DIRECTORY" --parallel

# 3. Build the AppDir layout.
rm -rf "${APP_DIR:?}"
mkdir -p "$APP_DIR/usr/bin"
mkdir -p "$APP_DIR/usr/lib"
mkdir -p "$APP_DIR/usr/lib/fs-user-stories/core"
mkdir -p "$APP_DIR/usr/share/applications"
mkdir -p "$APP_DIR/usr/share/icons/hicolor/256x256/apps"

cp "$BUILD_DIRECTORY/fs-user-stories" "$APP_DIR/usr/bin/fs-user-stories"
cp "$QT_PROJECT/core-bundle/fs-user-stories-core" \
    "$APP_DIR/usr/lib/fs-user-stories/core/fs-user-stories-core"
cp "$QT_PROJECT/resources/fs-user-stories.desktop" \
    "$APP_DIR/usr/share/applications/fs-user-stories.desktop"

# Qt 6.5+ requires xcb-cursor to initialize its X11 platform plugin. Some
# linuxdeploy releases do not discover it automatically because it is loaded
# dynamically, so bundle it explicitly.
XCB_CURSOR_LIBRARY=$(ldconfig -p 2>/dev/null | \
    awk '/libxcb-cursor\.so\.0 / { print $NF; exit }')
if [ -z "$XCB_CURSOR_LIBRARY" ]; then
    echo "libxcb-cursor0 is required to build the AppImage" >&2
    exit 1
fi
cp -L "$XCB_CURSOR_LIBRARY" "$APP_DIR/usr/lib/libxcb-cursor.so.0"

# linuxdeploy deliberately excludes parts of the OpenGL loader stack because
# they are commonly supplied by the host. That makes the resulting AppImage
# fail on a minimal installation before it can reach the system's actual GPU
# driver. Bundle the ABI-stable loader libraries while leaving vendor drivers
# (Mesa/NVIDIA/AMD) to the operating system.
for GRAPHICS_LIBRARY in \
    libOpenGL.so.0 \
    libGL.so.1 \
    libGLX.so.0 \
    libEGL.so.1 \
    libGLdispatch.so.0 \
    libfontconfig.so.1 \
    libfreetype.so.6 \
    libexpat.so.1 \
    libX11.so.6 \
    libX11-xcb.so.1 \
    libxcb.so.1
do
    GRAPHICS_LIBRARY_PATH=$(ldconfig -p 2>/dev/null | \
        awk -v library="$GRAPHICS_LIBRARY" '$1 == library { print $NF; exit }')
    if [ -z "$GRAPHICS_LIBRARY_PATH" ]; then
        echo "$GRAPHICS_LIBRARY is required to build the AppImage" >&2
        exit 1
    fi
    cp -L "$GRAPHICS_LIBRARY_PATH" "$APP_DIR/usr/lib/$GRAPHICS_LIBRARY"
done

# libfontconfig also needs its runtime configuration, not just the shared
# library. Keep it inside the AppImage so a minimal desktop does not have to
# provide /etc/fonts.
if [ -d /etc/fonts ]; then
    mkdir -p "$APP_DIR/usr/etc"
    cp -R /etc/fonts "$APP_DIR/usr/etc/fonts"
fi

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
if [ -n "$QT_ROOT" ]; then
    export QMAKE="$QT_ROOT/bin/qmake"
    PATH="$QT_ROOT/bin:$PATH"
    export PATH
fi
mkdir -p "$OUTPUT_DIR"
rm -f "$APPIMAGE_OUTPUT"
export OUTPUT="$APPIMAGE_OUTPUT"
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

if [ ! -s "$APPIMAGE_OUTPUT" ]; then
    echo "AppImage was not created: $APPIMAGE_OUTPUT" >&2
    exit 1
fi

echo "AppImage written to $APPIMAGE_OUTPUT"
