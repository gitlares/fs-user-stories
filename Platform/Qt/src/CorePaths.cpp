// SPDX-License-Identifier: MIT
#include "CorePaths.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QStandardPaths>
#include <cstdlib>

namespace fsuserstories {

QString CorePaths::xdgDataHome()
{
#if defined(Q_OS_LINUX)
    if (const char *env = std::getenv("XDG_DATA_HOME"); env && *env) {
        return QString::fromLocal8Bit(env);
    }
    return QDir::homePath() + QStringLiteral("/.local/share");
#elif defined(Q_OS_WIN)
    // %LOCALAPPDATA%\fs-user-stories  (independent from org/app names).
    const QString local = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    return local.isEmpty() ? QDir::homePath() + QStringLiteral("/AppData/Local") : local;
#else
    // macOS / other Unix: use the per-user app-local data directory
    // (~/Library/Application Support on macOS). This keeps Qt's data co-located
    // with the rest of the user's macOS app data, mirroring the macOS Swift
    // build's layout at "FS User Stories/fs-user-stories.sqlite3".
    const QString base = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    return base.isEmpty() ? QDir::homePath() + QStringLiteral("/.local/share") : base;
#endif
}

QString CorePaths::defaultDatabasePath()
{
    const QString base = xdgDataHome() + QStringLiteral("/fs-user-stories");
    QDir().mkpath(base);
    return base + QStringLiteral("/workspace.sqlite");
}

QString CorePaths::defaultAttachmentsRoot()
{
    const QString base = xdgDataHome() + QStringLiteral("/fs-user-stories/attachments");
    QDir().mkpath(base);
    return base;
}

QString CorePaths::defaultRepositoriesRoot()
{
    const QString base = xdgDataHome() + QStringLiteral("/fs-user-stories/repositories");
    QDir().mkpath(base);
    return base;
}

QString CorePaths::resolveCoreExecutable()
{
    if (const char *env = std::getenv("FS_USER_STORIES_CORE"); env && *env) {
        const QString path = QString::fromLocal8Bit(env);
        if (QFileInfo::exists(path)) {
            return path;
        }
    }

    const QString exeDir = QCoreApplication::applicationDirPath();
#ifdef Q_OS_WIN
    const QString exeName = QStringLiteral("fs-user-stories-core.exe");
#else
    const QString exeName = QStringLiteral("fs-user-stories-core");
#endif

    const QList<QString> candidates = {
        exeDir + QLatin1Char('/') + exeName,
        exeDir + QStringLiteral("/core/") + exeName,
#ifndef Q_OS_WIN
        exeDir + QStringLiteral("/../lib/fs-user-stories/core/") + exeName,
        exeDir + QStringLiteral("/../share/fs-user-stories/core/") + exeName,
        exeDir + QStringLiteral("/../../core/") + exeName, // dev layout
#endif
    };

    for (const QString &path : candidates) {
        if (QFileInfo::exists(path)) {
            return QFileInfo(path).absoluteFilePath();
        }
    }

    return {};
}

} // namespace fsuserstories
