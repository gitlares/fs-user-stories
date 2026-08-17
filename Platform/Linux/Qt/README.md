# FS User Stories — Linux/Qt front-end

This directory hosts the Qt 6 / QML front-end for FS User Stories on Linux.
The Rust core is shared with the macOS build and lives in `../../../Core/`.

## Layout

```
Platform/Linux/Qt/
├── CMakeLists.txt         # Qt 6 + QML build configuration
├── src/
│   ├── main.cpp           # entry point, wires the CoreClient into QML
│   ├── CoreClient.{h,cpp} # spawns the Rust core, JSON stdin/stdout
│   ├── CorePaths.{h,cpp}  # data-root resolution, XDG paths
│   ├── WorkspaceController.*  # QObject exposed to QML as `workspace`
│   ├── StoryModel.*       # QAbstractListModel of search matches
│   ├── AppInfo.{h,cpp}    # app metadata
│   └── qml/               # QML views
├── resources/             # .desktop entry, icons
├── scripts/AppRun         # AppImage entry script
└── core-bundle/           # output of Scripts/build-core-linux.sh
```

## Quick start

```sh
# 1. Build the Rust core for Linux (must run on Linux).
./Scripts/build-core-linux.sh

# 2. Build the Qt app.
cmake -S Platform/Linux/Qt -B Platform/Linux/Qt/build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release
cmake --build Platform/Linux/Qt/build --parallel

# 3. Run.
./Platform/Linux/Qt/build/fs-user-stories
```

For AppImage packaging, see `Scripts/build-linux-app.sh` and
`docs/linux-build.md`.
