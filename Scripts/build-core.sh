#!/bin/sh
set -eu

SCRIPT_DIRECTORY=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIRECTORY=$(dirname "$SCRIPT_DIRECTORY")
CORE_DIRECTORY="$PROJECT_DIRECTORY/Core"
RESOURCE_DIRECTORY="$PROJECT_DIRECTORY/Sources/FSUserStoriesApp/Resources/Core"
APPLE_SILICON_TARGET="aarch64-apple-darwin"

if ! command -v cargo >/dev/null 2>&1; then
    echo "Rust and Cargo are required to build the core." >&2
    exit 1
fi

if ! command -v cmake >/dev/null 2>&1; then
    echo "CMake is required only while building the vendored libgit2 dependency." >&2
    exit 1
fi

mkdir -p "$RESOURCE_DIRECTORY"
cargo build --manifest-path "$CORE_DIRECTORY/Cargo.toml" --release --locked --target "$APPLE_SILICON_TARGET"
cp "$CORE_DIRECTORY/target/$APPLE_SILICON_TARGET/release/fs-user-stories-core" "$RESOURCE_DIRECTORY/fs-user-stories-core"
chmod 755 "$RESOURCE_DIRECTORY/fs-user-stories-core"

if ! lipo -archs "$RESOURCE_DIRECTORY/fs-user-stories-core" | grep -qx 'arm64'; then
    echo "The bundled Rust core must contain only the arm64 architecture." >&2
    exit 1
fi

echo "Bundled Rust core updated at $RESOURCE_DIRECTORY/fs-user-stories-core"
