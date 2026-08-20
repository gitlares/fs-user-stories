#!/bin/sh
# SPDX-License-Identifier: MIT

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
distribution_dir="$project_dir/Distribution"
app_name="FS User Stories"
app_bundle="$distribution_dir/$app_name.app"
dmg_path="$distribution_dir/FS-User-Stories-1.0.4.dmg"
core_source="$project_dir/Sources/FSUserStoriesApp/Resources/Core/fs-user-stories-core"

cd "$project_dir"

if [ ! -x "$core_source" ]; then
    echo "The generated Rust core is missing." >&2
    echo "Run Scripts/build-core.sh before packaging." >&2
    exit 1
fi

swift build -c release
binary_dir=$(swift build -c release --show-bin-path)
resource_bundle="$binary_dir/FSUserStories_FSUserStoriesApp.bundle"

if [ ! -x "$binary_dir/FSUserStories" ]; then
    echo "Release executable was not produced." >&2
    exit 1
fi

if [ ! -d "$resource_bundle" ]; then
    echo "Swift package resources were not produced." >&2
    exit 1
fi

mkdir -p "$distribution_dir"
rm -rf "$app_bundle"
rm -f "$dmg_path"

mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
cp "$binary_dir/FSUserStories" "$app_bundle/Contents/MacOS/FSUserStories"
cp "$project_dir/Support/Info.plist" "$app_bundle/Contents/Info.plist"
cp "$project_dir/Support/AppIcon.icns" "$app_bundle/Contents/Resources/AppIcon.icns"
cp -R "$resource_bundle" "$app_bundle/Contents/Resources/"
chmod +x "$app_bundle/Contents/MacOS/FSUserStories"
chmod +x "$app_bundle/Contents/Resources/FSUserStories_FSUserStoriesApp.bundle/fs-user-stories-core"

plutil -lint "$app_bundle/Contents/Info.plist"

staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/fs-user-stories-dmg.XXXXXX")
trap 'rm -rf "$staging_dir"' EXIT
cp -R "$app_bundle" "$staging_dir/"
ln -s /Applications "$staging_dir/Applications"

hdiutil create \
    -volname "$app_name 1.0.4" \
    -srcfolder "$staging_dir" \
    -format UDZO \
    -ov \
    "$dmg_path"

echo "Created unsigned release artifacts:"
echo "  $app_bundle"
echo "  $dmg_path"
echo "Signing and notarization must be performed by the human release owner."
