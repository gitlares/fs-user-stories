# Building FS User Stories on Linux (Qt 6 front-end)

This document covers building the Linux/Qt front-end and the Rust core for
Linux targets. The Qt GUI is shared across Linux, macOS and Windows and lives
under `Platform/Qt/`; the Rust core lives in `Core/`.

## 1. Toolchain

### Ubuntu / Debian 22.04+

```sh
sudo apt update
sudo apt install -y \
    build-essential cmake ninja-build pkg-config git curl \
    libsecret-1-dev
```

Install a Qt 6.5 or newer desktop kit. Qt 6.7.3 `gcc_64` is the tested kit;
Ubuntu 24.04's Qt 6.4 packages are too old. With the Qt Online Installer's
default location:

```sh
export FS_USER_STORIES_QT_ROOT="$HOME/Qt/6.7.3/gcc_64"
```

### Rust

```sh
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
rustup target add x86_64-unknown-linux-gnu
```

### AppImage tooling

```sh
sudo apt install -y wget file fuse
sudo wget -O /usr/local/bin/linuxdeploy \
    https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
sudo wget -O /usr/local/bin/linuxdeploy-plugin-qt \
    https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage
sudo chmod +x /usr/local/bin/linuxdeploy*
```

## 2. Build the Rust core

```sh
./Scripts/build-core-linux.sh
```

The output is written to `Platform/Qt/core-bundle/fs-user-stories-core`.

## 3. Build the Qt app

```sh
cmake -S Platform/Qt -B Platform/Qt/build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_PREFIX_PATH="$FS_USER_STORIES_QT_ROOT"
cmake --build Platform/Qt/build --parallel
```

Run it for a quick smoke test:

```sh
FS_USER_STORIES_CORE="$PWD/Platform/Qt/core-bundle/fs-user-stories-core" \
    ./Platform/Qt/build/fs-user-stories
```

## 4. Build an AppImage

```sh
./Scripts/build-linux-app.sh
```

The AppImage is written to `Distribution/Linux/FSUserStories-x86_64.AppImage`.

## 5. Architecture notes

- The Rust core keeps its macOS JSON command protocol. The Qt GUI exchanges
  the same JSON via stdin/stdout, mirroring
  `Sources/FSUserStoriesApp/Infrastructure/Git/RustCoreClient.swift`.
- No Swift code is referenced at runtime. The Qt binary is a self-contained
  front-end that loads the Rust core as a child process.
- On Linux, the workspace database lives in
  `~/.local/share/fs-user-stories/workspace.sqlite`. Attachments stay under
  `~/.local/share/fs-user-stories/attachments`. Override with the
  `XDG_DATA_HOME` environment variable.
- The data root layout is intentionally XDG-compliant so distributions can
  package the binary as a `.deb` later without collisions.

## 6. Qt GUI scope

The Qt application includes project, profile and story CRUD; acceptance
criteria and notes; portable attachments; automatic Git synchronization;
GitHub Device Flow and collaborator invitations; and the local MCP server.
On Linux, clicking an attachment reveals its managed copy in an installed
file manager.
