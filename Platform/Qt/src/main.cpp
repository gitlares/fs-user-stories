// SPDX-License-Identifier: MIT
#include <QGuiApplication>
#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QStandardPaths>
#include <QIcon>
#include <QLoggingCategory>

#include "AppInfo.h"
#include "CoreClient.h"
#include "CorePaths.h"
#include "WorkspaceController.h"

using namespace fsuserstories;

int main(int argc, char *argv[])
{
    QCoreApplication::setApplicationName(AppInfo::name());
    QCoreApplication::setOrganizationName(AppInfo::organization());
    QCoreApplication::setOrganizationDomain(AppInfo::domain());
    QCoreApplication::setApplicationVersion(AppInfo::version());

    QApplication app(argc, argv);
    QApplication::setWindowIcon(QIcon::fromTheme(QStringLiteral("fs-user-stories")));
    QQuickStyle::setStyle(QStringLiteral("Fusion"));

    const QString corePath = CorePaths::resolveCoreExecutable();
    if (corePath.isEmpty()) {
        qFatal("Could not locate fs-user-stories-core(.exe). Set $FS_USER_STORIES_CORE "
               "or place it next to fs-user-stories.exe (or in a 'core/' subdirectory).");
    }

    auto client = std::make_unique<CoreClient>(corePath, QStringList{},
                                               CoreClient::Mode::OneShot);
    // No startup probe: OneShot mode lazily spawns the core on the first
    // command (controller.load() below). The Swift bridge follows the same
    // pattern. We rely on the controller error path to surface failures.

    WorkspaceController controller;
    controller.setCoreClient(std::move(client), corePath);
    QObject::connect(&controller, &WorkspaceController::info,
                     &app, [](const QString &message) {
                         qInfo().noquote() << message;
                     });
    QObject::connect(&controller, &WorkspaceController::lastErrorChanged,
                     &controller, [&]() {
                         if (!controller.lastError().isEmpty()) {
                             qWarning().noquote() << controller.lastError();
                         }
                     });

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("workspace", &controller);
    engine.rootContext()->setContextProperty("appInfo",
        QVariantMap{
            {"name", AppInfo::name()},
            {"version", AppInfo::version()},
            {"corePath", corePath},
        });
    engine.loadFromModule("FSUserStories", "Main");
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }

    controller.load();
    return app.exec();
}
