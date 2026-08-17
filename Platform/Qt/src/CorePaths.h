// SPDX-License-Identifier: MIT
#pragma once

#include <QString>

namespace fsuserstories {

/// Resolves filesystem locations used by the Qt front-end.
///
/// All paths are portable across Linux, macOS and Windows:
///   * Linux:    honours `$XDG_DATA_HOME`, otherwise `~/.local/share/fs-user-stories/`
///   * macOS:    `~/Library/Application Support/fs-user-stories/`
///   * Windows:  `%LOCALAPPDATA%\fs-user-stories\fs-user-stories\`
class CorePaths
{
public:
    /// Returns the path to the bundled `fs-user-stories-core` binary, or an
    /// empty string if not found. The search order is:
    ///   1. `$FS_USER_STORIES_CORE` (override)
    ///   2. `<bindir>/fs-user-stories-core` (sibling of the packaged binary)
    ///   3. `<bindir>/../lib/fs-user-stories/core/fs-user-stories-core`  (Linux)
    ///   4. `<bindir>/../share/fs-user-stories/core/fs-user-stories-core` (Linux)
    ///   5. `<bindir>/../../core/fs-user-stories-core`                   (Linux dev layout)
    ///   6. `<bindir>/core/fs-user-stories-core`                         (Windows)
    static QString resolveCoreExecutable();

    /// Returns the workspace database path used by the UI.
    /// Defaults to `<appData>/fs-user-stories/workspace.sqlite`.
    static QString defaultDatabasePath();

    /// Returns the attachments root.
    /// Defaults to `<appData>/fs-user-stories/attachments`.
    static QString defaultAttachmentsRoot();

    /// Returns the repositories directory.
    /// Defaults to `<appData>/fs-user-stories/repositories`.
    static QString defaultRepositoriesRoot();

    /// Returns the platform-appropriate per-user data directory.
    /// On Linux this is XDG-style (`$XDG_DATA_HOME` or `~/.local/share`).
    /// On macOS and Windows this is `QStandardPaths::AppLocalDataLocation`.
    static QString xdgDataHome();
};

} // namespace fsuserstories
