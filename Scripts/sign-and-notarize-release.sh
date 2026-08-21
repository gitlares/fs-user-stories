#!/bin/sh
# SPDX-License-Identifier: MIT

set -eu

: "${FS_SIGNING_IDENTITY:?Set FS_SIGNING_IDENTITY to a Developer ID Application identity}"
: "${FS_SIGNING_KEYCHAIN:?Set FS_SIGNING_KEYCHAIN to the signing Keychain path}"
: "${FS_NOTARY_PROFILE:?Set FS_NOTARY_PROFILE to a notarytool Keychain profile}"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
distribution_dir="$project_dir/Distribution"
app_bundle="$distribution_dir/FS User Stories.app"
core_executable="$app_bundle/Contents/Resources/FSUserStories_FSUserStoriesApp.bundle/fs-user-stories-core"
dmg_path="$distribution_dir/FS-User-Stories-1.0.8.dmg"

if [ ! -d "$app_bundle" ] || [ ! -x "$core_executable" ]; then
    echo "Run Scripts/package-release.sh before signing." >&2
    exit 1
fi

codesign --force --options runtime --timestamp \
    --keychain "$FS_SIGNING_KEYCHAIN" \
    --sign "$FS_SIGNING_IDENTITY" \
    "$core_executable"

codesign --force --options runtime --timestamp \
    --keychain "$FS_SIGNING_KEYCHAIN" \
    --sign "$FS_SIGNING_IDENTITY" \
    "$app_bundle"

codesign --verify --deep --strict --verbose=2 "$app_bundle"

rm -f "$dmg_path"
staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/fs-user-stories-signed-dmg.XXXXXX")
trap 'rm -rf "$staging_dir"' EXIT
cp -R "$app_bundle" "$staging_dir/"
ln -s /Applications "$staging_dir/Applications"

hdiutil create \
    -volname "FS User Stories 1.0.8" \
    -srcfolder "$staging_dir" \
    -format UDZO \
    -ov \
    "$dmg_path"

codesign --force --timestamp \
    --keychain "$FS_SIGNING_KEYCHAIN" \
    --sign "$FS_SIGNING_IDENTITY" \
    "$dmg_path"
codesign --verify --verbose=2 "$dmg_path"

xcrun notarytool submit "$dmg_path" \
    --keychain-profile "$FS_NOTARY_PROFILE" \
    --wait

xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
spctl --assess --type open --context context:primary-signature \
    --verbose=2 "$dmg_path"

echo "Signed, notarized, and verified:"
echo "  $dmg_path"
