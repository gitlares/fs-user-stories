// SPDX-License-Identifier: MIT
#include <QGuiApplication>
#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QStandardPaths>
#include <QIcon>
#include <QFontDatabase>
#include <QFont>
#include <QFile>
#include <QDir>
#include <QLoggingCategory>

#include "AppInfo.h"
#include "CoreClient.h"
#include "CorePaths.h"
#include "WorkspaceController.h"

using namespace fsuserstories;

// String identifiers used by QML for icon ligatures that map to
// Material Symbols glyphs (the open-source cousin of Apple SF Symbols).
// Use these as the `text` of a Label whose `font.family` is set via the
// `appIconFont` context property (added below).
namespace IconLigatures {
    constexpr auto Refresh       = "refresh";
    constexpr auto Sync          = "sync";
    constexpr auto More          = "more_horiz";
    constexpr auto Plus          = "add";
    constexpr auto NewProject    = "create_new_folder";
    constexpr auto JoinShared    = "person_add";
    constexpr auto AddProfile    = "person_add";
    constexpr auto AddStory      = "edit_square";
    constexpr auto Edit          = "edit";
    constexpr auto Folder        = "folder";
    constexpr auto Done          = "check_circle";
    constexpr auto Active        = "play_circle";
    constexpr auto Draft         = "edit_note";
    constexpr auto Check         = "check";
    constexpr auto Lock          = "lock";
    constexpr auto Stories       = "book";
    constexpr auto Profiles      = "group";
    constexpr auto Search        = "search";
    constexpr auto Trash         = "delete";
    constexpr auto About         = "info";
    constexpr auto External      = "open_in_new";
    constexpr auto Running       = "hourglass_top";
    constexpr auto Error         = "error";
}

int main(int argc, char *argv[])
{
    QCoreApplication::setApplicationName(AppInfo::name());
    QCoreApplication::setOrganizationName(AppInfo::organization());
    QCoreApplication::setOrganizationDomain(AppInfo::domain());
    QCoreApplication::setApplicationVersion(AppInfo::version());

    QApplication app(argc, argv);
    QApplication::setWindowIcon(QIcon::fromTheme(QStringLiteral("fs-user-stories")));

    // Load Material Symbols Outlined (OFL-licensed, OFL file bundled at
    // <bindir>/resources/fonts/MaterialSymbolsOutlined-Variable.woff2 by the
    // POST_BUILD step in CMakeLists). Returns the family name to use in QML.
    QString iconFontFamily = QStringLiteral("Material Symbols Outlined");
    const QString fontPath =
        QCoreApplication::applicationDirPath() +
        QStringLiteral("/resources/fonts/MaterialSymbolsOutlined-Variable.woff2");
    if (QFile::exists(fontPath)) {
        const int fontId = QFontDatabase::addApplicationFont(fontPath);
        if (fontId >= 0) {
            const QStringList families = QFontDatabase::applicationFontFamilies(fontId);
            if (!families.isEmpty()) {
                iconFontFamily = families.first();
            }
        }
    }

    // Default font for the app: system default body, sized for the platform.
    QFont uiFont = app.font();
#ifdef Q_OS_WIN
    uiFont.setPointSize(10);
#elif defined(Q_OS_LINUX)
    uiFont.setPointSize(10);
#endif
    app.setFont(uiFont);

    QQuickStyle::setStyle(QStringLiteral("Fusion"));

    const QString corePath = CorePaths::resolveCoreExecutable();
    if (corePath.isEmpty()) {
        qFatal("Could not locate fs-user-stories-core(.exe). Set $FS_USER_STORIES_CORE "
               "or place it next to fs-user-stories.exe (or in a 'core/' subdirectory).");
    }

    auto client = std::make_unique<CoreClient>(corePath, QStringList{},
                                               CoreClient::Mode::OneShot);

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
    engine.rootContext()->setContextProperty("appIconFont", iconFontFamily);
    engine.rootContext()->setContextProperty("appIcons", QString());
    engine.loadFromModule("FSUserStories", "Main");
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }

    controller.load();
    return app.exec();
}
