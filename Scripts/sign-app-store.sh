#!/bin/sh
# SPDX-License-Identifier: MIT

# Human-operated App Store packaging. This script cannot upload a build and it
# refuses to run unless the human supplies the proper App Store credentials.

set -eu

: "${FS_APP_STORE_APP_IDENTITY:?Set the Apple Distribution signing identity}"
: "${FS_APP_STORE_INSTALLER_IDENTITY:?Set the Mac App Store installer signing identity}"
: "${FS_APP_STORE_PROVISIONING_PROFILE:?Set the path to the App Store provisioning profile}"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
distribution_dir="$project_dir/Distribution/AppStore"
app_bundle="$distribution_dir/FS User Stories.app"
core_executable="$app_bundle/Contents/Resources/FSUserStories_FSUserStoriesApp.bundle/fs-user-stories-core"
package_path="$distribution_dir/FS-User-Stories-App-Store.pkg"

if [ ! -d "$app_bundle" ] || [ ! -x "$core_executable" ]; then
    echo "Run Scripts/package-app-store.sh before signing." >&2
    exit 1
fi

if [ ! -f "$FS_APP_STORE_PROVISIONING_PROFILE" ]; then
    echo "The App Store provisioning profile was not found." >&2
    exit 1
fi

cp "$FS_APP_STORE_PROVISIONING_PROFILE" "$app_bundle/Contents/embedded.provisionprofile"

codesign --force --sign "$FS_APP_STORE_APP_IDENTITY" \
    --entitlements "$project_dir/Support/AppStore/Core.entitlements" \
    "$core_executable"

codesign --force --sign "$FS_APP_STORE_APP_IDENTITY" \
    --entitlements "$project_dir/Support/AppStore/App.entitlements" \
    "$app_bundle"
codesign --verify --deep --strict --verbose=2 "$app_bundle"

rm -f "$package_path"
productbuild --component "$app_bundle" /Applications \
    --sign "$FS_APP_STORE_INSTALLER_IDENTITY" \
    "$package_path"

pkgutil --check-signature "$package_path"
echo "Created App Store upload package: $package_path"
echo "Upload it manually with Transporter or Xcode after human review."
