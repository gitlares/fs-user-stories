# Building FS User Stories on Linux

This document covers building the Linux/Qt front-end and the Rust core for
Linux targets. The Qt GUI is **new** and lives on the `feature/linux-qt`
branch; the Rust core is shared with the macOS build and lives in `Core/`.

## 1. Toolchain

### Ubuntu / Debian 22.04+

```sh
sudo apt update
sudo apt install -y \
    build-essential cmake ninja-build pkg-config git curl \
    qt6-base-dev qt6-declarative-dev qt6-tools-dev \
    qt6-quickcontrols2-dev qml6-module-qtquick \
    qml6-module-qtquick-controls qml6-module-qtquick-layouts \
    qml6-module-qtquick-window qml6-module-qtquick-dialogs \
    qml6-module-qtquick-templates qml6-module-qtqml-workerscript \
    libssl-dev libgit2-dev librust-libgit2-sys-dev
```

The Rust core vendors libgit2/openssl via `git2` features `vendored-libgit2`
and `vendored-openssl`, so the `libgit2-dev` packages above are optional
(skip them if you don't want to use the system libgit2).

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

The output is written to `Platform/Linux/Qt/core-bundle/fs-user-stories-core`.

## 3. Build the Qt app

```sh
cmake -S Platform/Linux/Qt -B Platform/Linux/Qt/build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release
cmake --build Platform/Linux/Qt/build --parallel
```

Run it for a quick smoke test:

```sh
./Platform/Linux/Qt/build/fs-user-stories
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

## 6. Current scope of the Qt GUI

The first iteration (this branch) ships:

- Welcome view, project list, project creation flow.
- Three-pane workspace (project list / story list / story detail).
- Story creation, edit, and delete.
- Search, status filter, profile filter.
- Export / import Markdown.
- Footer status bar with the running core path.

The following workflows are placeholder views and will be filled in after
the basic round-trip with the core is stable:

- Project profiles (UI scaffolding present in `ProjectProfilesView.qml`).
- Git sync UI (`GitSyncView.qml`).
- GitHub Device Flow, conflict resolution, and MCP server management.
- Attachments and QuickLook equivalent.
