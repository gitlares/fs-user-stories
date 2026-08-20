#!/bin/sh
# SPDX-License-Identifier: MIT

# Builds an unsigned, sandbox-configured .app suitable for local App Store
# validation. It never signs, uploads, notarizes, or changes a public branch.

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
distribution_dir="$project_dir/Distribution/AppStore"
app_name="FS User Stories"
app_bundle="$distribution_dir/$app_name.app"
core_source="$project_dir/Sources/FSUserStoriesApp/Resources/Core/fs-user-stories-core"

require_arm64_only() {
    binary_path="$1"
    architectures=$(lipo -archs "$binary_path")
    if [ "$architectures" != "arm64" ]; then
        echo "Expected an Apple Silicon-only arm64 binary, got: $architectures" >&2
        exit 1
    fi
}

cd "$project_dir"

if [ ! -x "$core_source" ]; then
    echo "The generated Rust core is missing. Run Scripts/build-core.sh first." >&2
    exit 1
fi

swift build -c release --arch arm64
binary_dir=$(swift build -c release --arch arm64 --show-bin-path)
resource_bundle="$binary_dir/FSUserStories_FSUserStoriesApp.bundle"

if [ ! -x "$binary_dir/FSUserStories" ] || [ ! -d "$resource_bundle" ]; then
    echo "The Swift release build or its resources are missing." >&2
    exit 1
fi

rm -rf "$app_bundle"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
cp "$binary_dir/FSUserStories" "$app_bundle/Contents/MacOS/FSUserStories"
cp "$project_dir/Support/AppStore/Info.plist" "$app_bundle/Contents/Info.plist"
cp "$project_dir/Support/AppIcon.icns" "$app_bundle/Contents/Resources/AppIcon.icns"
cp "$project_dir/Support/AppStore/PrivacyInfo.xcprivacy" "$app_bundle/Contents/Resources/PrivacyInfo.xcprivacy"
cp -R "$resource_bundle" "$app_bundle/Contents/Resources/"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string com.fsuserstories.app.resources' \
    "$app_bundle/Contents/Resources/FSUserStories_FSUserStoriesApp.bundle/Info.plist"
chmod +x "$app_bundle/Contents/MacOS/FSUserStories"
chmod +x "$app_bundle/Contents/Resources/FSUserStories_FSUserStoriesApp.bundle/fs-user-stories-core"

require_arm64_only "$app_bundle/Contents/MacOS/FSUserStories"
require_arm64_only "$app_bundle/Contents/Resources/FSUserStories_FSUserStoriesApp.bundle/fs-user-stories-core"

plutil -lint "$app_bundle/Contents/Info.plist"
plutil -lint "$app_bundle/Contents/Resources/PrivacyInfo.xcprivacy"

echo "Created unsigned App Store candidate:"
echo "  $app_bundle"
echo "Use Scripts/sign-app-store.sh only after a human creates the App Store provisioning profile."
