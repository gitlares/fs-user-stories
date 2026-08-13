#!/bin/sh
# SPDX-License-Identifier: MIT

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
app_bundle="$project_dir/Distribution/FS User Stories.app"
open_app=true
run_tests=false

usage() {
    cat <<'EOF'
Usage: ./Scripts/build-and-run-local.sh [--test] [--no-open]

Builds the Rust core and an unsigned local macOS application entirely from source.

Options:
  --test     Run the Swift and Rust test suites before packaging.
  --no-open  Build the application without opening it.
  --help     Show this help message.
EOF
}

for argument in "$@"; do
    case "$argument" in
        --test) run_tests=true ;;
        --no-open) open_app=false ;;
        --help|-h) usage; exit 0 ;;
        *)
            echo "Unknown option: $argument" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ "$(uname -s)" != "Darwin" ] || [ "$(uname -m)" != "arm64" ]; then
    echo "FS User Stories Alpha currently builds only on Apple Silicon Macs." >&2
    exit 1
fi

macos_major=$(sw_vers -productVersion | cut -d. -f1)
if [ "$macos_major" -lt 26 ]; then
    echo "macOS 26 or later is required. Found macOS $(sw_vers -productVersion)." >&2
    exit 1
fi

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    export DEVELOPER_DIR
fi

for command_name in xcrun swift cargo cmake; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Missing required command: $command_name" >&2
        echo "See the Build from source section in README.md." >&2
        exit 1
    fi
done

cd "$project_dir"

echo "Building the Rust core from source..."
"$script_dir/build-core.sh"

if [ "$run_tests" = true ]; then
    echo "Running Swift tests..."
    swift test
    echo "Running Rust tests..."
    cargo test --manifest-path "$project_dir/Core/Cargo.toml" --locked
fi

echo "Packaging the local macOS application..."
"$script_dir/package-alpha.sh"

if [ "$open_app" = true ]; then
    echo "Opening $app_bundle"
    open -n "$app_bundle"
fi

echo "Local build ready:"
echo "  $app_bundle"
