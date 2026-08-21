# Releasing FS User Stories 1.0.6 for macOS

FS User Stories deliberately separates reproducible packaging from release-owner
operations. The packaging script never accesses a signing identity, Apple ID,
notarization credential, or Git credential.

## 1. Build the unsigned artifacts

From the repository root:

```sh
./Scripts/package-release.sh
```

This creates:

- `Distribution/FS User Stories.app`
- `Distribution/FS-User-Stories-1.0.6.dmg`

Both artifacts currently target Apple Silicon.

## 2. Sign the application manually

The human release owner needs an Apple Developer Program membership and a
**Developer ID Application** certificate installed in Keychain. Replace the
example identity with the exact certificate name shown by Keychain Access.

Sign the bundled core first and the outer application second:

```sh
export FS_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"

codesign --force --options runtime --timestamp \
  --sign "$FS_SIGNING_IDENTITY" \
  "Distribution/FS User Stories.app/Contents/Resources/FSUserStories_FSUserStoriesApp.bundle/fs-user-stories-core"

codesign --force --options runtime --timestamp \
  --sign "$FS_SIGNING_IDENTITY" \
  "Distribution/FS User Stories.app"

codesign --verify --deep --strict --verbose=2 \
  "Distribution/FS User Stories.app"
```

These commands must be run by the human release owner. Do not place certificate
names or credentials in the repository.

The same signing, DMG recreation, notarization, stapling, and Gatekeeper checks
can be performed with the repository helper after reviewing its inputs:

```sh
FS_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
FS_SIGNING_KEYCHAIN="/absolute/path/to/signing.keychain-db" \
FS_NOTARY_PROFILE="FSUserStories-Notary" \
./Scripts/sign-and-notarize-release.sh
```

## 3. Recreate and sign the DMG manually

After signing the application, recreate the disk image so it contains the signed
bundle:

```sh
rm "Distribution/FS-User-Stories-1.0.6.dmg"
staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/fs-user-stories-release.XXXXXX")
cp -R "Distribution/FS User Stories.app" "$staging_dir/"
ln -s /Applications "$staging_dir/Applications"
hdiutil create -volname "FS User Stories 1.0.6" \
  -srcfolder "$staging_dir" -format UDZO -ov \
  "Distribution/FS-User-Stories-1.0.6.dmg"
rm -rf "$staging_dir"

codesign --force --timestamp \
  --sign "$FS_SIGNING_IDENTITY" \
  "Distribution/FS-User-Stories-1.0.6.dmg"
```

## 4. Notarize and staple manually

Create a Keychain profile once using `xcrun notarytool store-credentials`, then:

```sh
xcrun notarytool submit "Distribution/FS-User-Stories-1.0.6.dmg" \
  --keychain-profile "FSUserStories-Notary" --wait

xcrun stapler staple "Distribution/FS-User-Stories-1.0.6.dmg"
xcrun stapler validate "Distribution/FS-User-Stories-1.0.6.dmg"
spctl --assess --type open --context context:primary-signature \
  --verbose=2 "Distribution/FS-User-Stories-1.0.6.dmg"
```

## 5. Publish manually

Create the commit and tag with the human Git identity, then create a GitHub
prerelease and upload the signed, notarized DMG. `Distribution/` is ignored so
release binaries are not accidentally added to source control.

Before sharing the link, download the release artifact on a different Mac and
verify installation, first launch, local persistence, MCP availability, GitHub
authorization, private repository creation, and synchronization between two
machines.
