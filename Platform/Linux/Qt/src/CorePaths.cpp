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
    if (const char *env = std::getenv("XDG_DATA_HOME"); env && *env) {
        return QString::fromLocal8Bit(env);
    }
    return QDir::homePath() + QStringLiteral("/.local/share");
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
    const QString exeName = QStringLiteral("fs-user-stories-core");

    const QList<QString> candidates = {
        exeDir + QLatin1Char('/') + exeName,
        exeDir + QStringLiteral("/../lib/fs-user-stories/core/") + exeName,
        exeDir + QStringLiteral("/../share/fs-user-stories/core/") + exeName,
        exeDir + QStringLiteral("/../../core/") + exeName, // dev layout
    };

    for (const QString &path : candidates) {
        if (QFileInfo::exists(path)) {
            return QFileInfo(path).absoluteFilePath();
        }
    }

    return {};
}

} // namespace fsuserstories
