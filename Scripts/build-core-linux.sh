#!/bin/sh
# Builds the Rust core cross-compiled for x86_64 Linux from macOS.
# Requires: rustup target add x86_64-unknown-linux-gnu, and a Linux GCC
# toolchain (e.g. via brew install FiloSottile/musl-cross/musl-cross or
# `apt install gcc-x86-64-linux-gnu` on Ubuntu).
#
# This script is intended to run on Linux. On macOS use the macOS core build
# script (`Scripts/build-core.sh`) and only when bundling for Linux is done on
# a Linux runner.

set -eu

SCRIPT_DIRECTORY=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIRECTORY=$(dirname "$SCRIPT_DIRECTORY")
CORE_DIRECTORY="$PROJECT_DIRECTORY/Core"
OUTPUT_DIRECTORY="$PROJECT_DIRECTORY/Platform/Qt/core-bundle"
TARGET=${FS_USER_STORIES_TARGET:-x86_64-unknown-linux-gnu}

if ! command -v cargo >/dev/null 2>&1; then
    echo "Rust and Cargo are required to build the core." >&2
    exit 1
fi

if ! command -v cmake >/dev/null 2>&1; then
    echo "CMake is required only while building the vendored libgit2 dependency." >&2
    exit 1
fi

# Auto-install target if missing.
if ! rustup target list --installed | grep -qx "$TARGET"; then
    echo "Installing Rust target $TARGET" >&2
    rustup target add "$TARGET"
fi

mkdir -p "$OUTPUT_DIRECTORY"
cargo build \
    --manifest-path "$CORE_DIRECTORY/Cargo.toml" \
    --release \
    --locked \
    --target "$TARGET"

cp "$CORE_DIRECTORY/target/$TARGET/release/fs-user-stories-core" \
    "$OUTPUT_DIRECTORY/fs-user-stories-core"
chmod 755 "$OUTPUT_DIRECTORY/fs-user-stories-core"

file "$OUTPUT_DIRECTORY/fs-user-stories-core"
echo "Bundled Linux core at $OUTPUT_DIRECTORY/fs-user-stories-core"
