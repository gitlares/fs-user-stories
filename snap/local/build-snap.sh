#!/bin/sh
# Snapcraft build hook for the Linux Qt front-end and Rust core.
#
# Magnolia provides Qt 6.7.3 through aqt at:
#   /home/dlares/Qt/6.7.3/gcc_64
# Set FS_USER_STORIES_QT_ROOT when building on another machine. linuxdeploy
# is used when available so Qt's QML modules and platform plugins are copied
# together; the fallback copies the same runtime tree explicitly.
set -eu

PROJECT_DIR="${CRAFT_PART_SRC:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}"
BUILD_DIR="${CRAFT_PART_BUILD:-$PROJECT_DIR/.snap-build}"
INSTALL_DIR="${CRAFT_PART_INSTALL:-$PROJECT_DIR/.snap-install}"

# Destructive builds on Magnolia run inside Snapcraft's sanitized environment,
# which omits the user-installed Rust toolchain from PATH.
if ! command -v rustup >/dev/null 2>&1 && \
   [ -x /home/dlares/.cargo/bin/rustup ]; then
    PATH="/home/dlares/.cargo/bin:$PATH"
    export PATH
fi

if ! command -v rustup >/dev/null 2>&1 || ! command -v cargo >/dev/null 2>&1; then
    echo "A current rustup-managed Rust toolchain is required" >&2
    exit 1
fi

QT_ROOT="${FS_USER_STORIES_QT_ROOT:-/home/dlares/Qt/6.7.3/gcc_64}"
QT_QMAKE="$QT_ROOT/bin/qmake6"

if [ ! -x "$QT_QMAKE" ]; then
    echo "Qt 6.7.3 was not found at $QT_ROOT" >&2
    echo "Set FS_USER_STORIES_QT_ROOT to a Qt 6.5+ gcc_64 kit." >&2
    exit 1
fi

export PATH="$QT_ROOT/bin:$PATH"
export CMAKE_PREFIX_PATH="$QT_ROOT${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export QML_SOURCES_PATHS="$PROJECT_DIR/Platform/Qt/src/qml"

"$PROJECT_DIR/Scripts/build-core-linux.sh"

QT_BUILD_DIR="$BUILD_DIR/qt-build"
cmake -S "$PROJECT_DIR/Platform/Qt" -B "$QT_BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$QT_ROOT"
cmake --build "$QT_BUILD_DIR" --parallel

rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/bin" "$INSTALL_DIR/usr/bin" "$INSTALL_DIR/usr/lib/fs-user-stories/core" \
    "$INSTALL_DIR/usr/share/applications" "$INSTALL_DIR/usr/share/icons/hicolor/256x256/apps"

cp "$PROJECT_DIR/snap/local/fs-user-stories.wrapper" \
    "$INSTALL_DIR/bin/fs-user-stories.wrapper"

cp "$PROJECT_DIR/Platform/Qt/core-bundle/fs-user-stories-core" \
    "$INSTALL_DIR/usr/lib/fs-user-stories/core/fs-user-stories-core"
cp "$PROJECT_DIR/Platform/Qt/resources/fs-user-stories.desktop" \
    "$INSTALL_DIR/usr/share/applications/fs-user-stories.desktop"
cp "$PROJECT_DIR/snap/gui/fs-user-stories.png" \
    "$INSTALL_DIR/usr/share/icons/hicolor/256x256/apps/fs-user-stories.png"

APP_DIR="$BUILD_DIR/AppDir"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/usr/bin" "$APP_DIR/usr/share/applications" \
    "$APP_DIR/usr/share/icons/hicolor/256x256/apps"
cp "$QT_BUILD_DIR/fs-user-stories" "$APP_DIR/usr/bin/fs-user-stories"
cp "$PROJECT_DIR/Platform/Qt/resources/fs-user-stories.desktop" \
    "$APP_DIR/usr/share/applications/fs-user-stories.desktop"
cp "$PROJECT_DIR/snap/gui/fs-user-stories.png" \
    "$APP_DIR/usr/share/icons/hicolor/256x256/apps/fs-user-stories.png"

if command -v linuxdeploy >/dev/null 2>&1 && command -v linuxdeploy-plugin-qt >/dev/null 2>&1; then
    linuxdeploy --appdir "$APP_DIR" \
        --desktop-file "$APP_DIR/usr/share/applications/fs-user-stories.desktop" \
        --icon-file "$APP_DIR/usr/share/icons/hicolor/256x256/apps/fs-user-stories.png" \
        --plugin qt
    cp -a "$APP_DIR/usr/." "$INSTALL_DIR/usr/"
else
    echo "linuxdeploy not found; copying Qt runtime from $QT_ROOT" >&2
    cp -a "$QT_ROOT/lib/." "$INSTALL_DIR/usr/lib/"
    cp -a "$QT_ROOT/plugins" "$INSTALL_DIR/usr/"
    cp -a "$QT_ROOT/qml" "$INSTALL_DIR/usr/"
    cp -a "$QT_BUILD_DIR/fs-user-stories" "$INSTALL_DIR/usr/bin/fs-user-stories"
fi

# linuxdeploy deliberately excludes libraries it expects from the host. A
# strictly confined snap cannot see those host libraries, so include the
# graphics/font/X11 baseline explicitly.
for LIBRARY_NAME in \
    libEGL.so.1 \
    libGL.so.1 \
    libGLX.so.0 \
    libGLdispatch.so.0 \
    libOpenGL.so.0 \
    libX11.so.6 \
    libX11-xcb.so.1 \
    libfontconfig.so.1 \
    libxcb.so.1
do
    LIBRARY_PATH=$(ldconfig -p 2>/dev/null | \
        awk -v name="$LIBRARY_NAME" '$1 == name { print $NF; exit }')
    if [ -z "$LIBRARY_PATH" ]; then
        echo "Required snap runtime library was not found: $LIBRARY_NAME" >&2
        exit 1
    fi
    cp -L "$LIBRARY_PATH" "$INSTALL_DIR/usr/lib/$LIBRARY_NAME"
done

# The application loads these fonts and its icon relative to the executable.
mkdir -p "$INSTALL_DIR/usr/bin/resources/fonts"
cp "$PROJECT_DIR/Platform/Qt/resources/fonts/MaterialSymbolsOutlined-Variable.ttf" \
    "$INSTALL_DIR/usr/bin/resources/fonts/"
cp "$PROJECT_DIR/Platform/Qt/resources/fonts/InterVariable.ttf" \
    "$INSTALL_DIR/usr/bin/resources/fonts/"
cp "$PROJECT_DIR/Design/AppIcon-master.png" \
    "$INSTALL_DIR/usr/bin/resources/app-icon.png"

chmod 755 "$INSTALL_DIR/bin/fs-user-stories.wrapper" \
    "$INSTALL_DIR/usr/bin/fs-user-stories" \
    "$INSTALL_DIR/usr/lib/fs-user-stories/core/fs-user-stories-core"
