#!/bin/sh
set -eu

SCRIPT_DIRECTORY=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIRECTORY=$(dirname "$SCRIPT_DIRECTORY")
CORE_DIRECTORY="$PROJECT_DIRECTORY/Core"
RESOURCE_DIRECTORY="$PROJECT_DIRECTORY/Sources/FSUserStoriesApp/Resources/Core"

if ! command -v cargo >/dev/null 2>&1; then
    echo "Rust and Cargo are required to build the core." >&2
    exit 1
fi

if ! command -v cmake >/dev/null 2>&1; then
    echo "CMake is required only while building the vendored libgit2 dependency." >&2
    exit 1
fi

mkdir -p "$RESOURCE_DIRECTORY"
cargo build --manifest-path "$CORE_DIRECTORY/Cargo.toml" --release --locked
cp "$CORE_DIRECTORY/target/release/fs-user-stories-core" "$RESOURCE_DIRECTORY/fs-user-stories-core"
chmod 755 "$RESOURCE_DIRECTORY/fs-user-stories-core"

echo "Bundled Rust core updated at $RESOURCE_DIRECTORY/fs-user-stories-core"
