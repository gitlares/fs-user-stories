# Mac App Store preparation

This folder defines the Mac App Store distribution configuration. It is not a
separate product: the Store build uses the same Swift interface and embedded
Rust core as the direct-download build.

## What changes for the Store

- The app is sandboxed.
- Network client access is required for optional Git synchronization.
- Network server access is required for the optional loopback-only MCP server.
- The Rust core inherits the application's sandbox.
- The Store build never inspects or terminates other processes to recover the
  MCP port. Its own lifecycle stops the embedded core on quit.

## Human-owned prerequisites

Do these in the Apple Developer account before signing:

1. Register the App ID `com.fsuserstories.app` if it is not already registered.
2. Create a **Mac App Store** provisioning profile for that App ID.
3. Ensure the signing machine has an **Apple Distribution** certificate and a
   **Mac App Store Installer** certificate.

No certificate, profile, password, token, or private key belongs in this
repository.

## Build and package

```sh
Scripts/build-core.sh
Scripts/package-app-store.sh
```

This produces an unsigned app at:

```text
Distribution/AppStore/FS User Stories.app
```

After a human reviews the result and supplies their Apple signing identities:

```sh
export FS_APP_STORE_APP_IDENTITY='Apple Distribution: …'
export FS_APP_STORE_INSTALLER_IDENTITY='Mac App Store Installer: …'
export FS_APP_STORE_PROVISIONING_PROFILE='/absolute/path/profile.provisionprofile'
Scripts/sign-app-store.sh
```

The result is an upload package at:

```text
Distribution/AppStore/FS-User-Stories-App-Store.pkg
```

Upload it manually through Transporter or Xcode. This repository does not
automate uploads, submissions, releases, or sales.
# Compatibility policy

The Mac App Store edition is Apple Silicon only (`arm64`) and requires macOS
26.0 or later. `Scripts/build-core.sh` and `Scripts/package-app-store.sh`
compile and validate that both executables contain only the `arm64`
architecture. Do not weaken these checks by adding an Intel slice.
