// SPDX-License-Identifier: MIT
#pragma once

#include <QString>

namespace fsuserstories {

/// Resolves the absolute path to the bundled `fs-user-stories-core` binary.
class CorePaths
{
public:
    /// Returns the path to the core binary, or an empty string if not found.
    /// The search order is:
    ///   1. $FS_USER_STORIES_CORE (override)
    ///   2. `<bindir>/fs-user-stories-core` (sibling of the AppImage binary)
    ///   3. `<bindir>/../lib/fs-user-stories/core/fs-user-stories-core`
    ///   4. `<prefix>/lib/fs-user-stories/core/fs-user-stories-core`
    ///   5. `core/fs-user-stories-core` next to the executable (dev layout)
    static QString resolveCoreExecutable();

    /// Returns the workspace database path used by the UI.
    /// Defaults to `~/.local/share/fs-user-stories/workspace.sqlite`.
    static QString defaultDatabasePath();

    /// Returns the attachments root. Defaults to
    /// `~/.local/share/fs-user-stories/attachments`.
    static QString defaultAttachmentsRoot();

    /// Returns `<core>/repositories` directory.
    static QString defaultRepositoriesRoot();

    /// Returns the standard XDG-style data directory (`XDG_DATA_HOME` or
    /// `~/.local/share`).
    static QString xdgDataHome();
};

} // namespace fsuserstories
