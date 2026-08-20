// SPDX-License-Identifier: MIT
#include <QGuiApplication>
#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QPalette>
#include <QQuickStyle>
#include <QStandardPaths>
#include <QIcon>
#include <QFontDatabase>
#include <QFont>
#include <QFile>
#include <QDir>
#include <QLoggingCategory>
#include <QTextStream>

#include "AppInfo.h"
#include "CoreClient.h"
#include "CorePaths.h"
#include "WorkspaceController.h"

using namespace fsuserstories;

namespace {
QFile *gDiagnosticFile = nullptr;

void diagnosticMessageHandler(QtMsgType type,
                              const QMessageLogContext &,
                              const QString &message)
{
    if (!gDiagnosticFile) {
        return;
    }
    const char *level = "INFO";
    if (type == QtWarningMsg) level = "WARNING";
    else if (type == QtCriticalMsg) level = "CRITICAL";
    else if (type == QtFatalMsg) level = "FATAL";
    else if (type == QtDebugMsg) level = "DEBUG";
    QTextStream stream(gDiagnosticFile);
    stream << level << ": " << message << '\n';
    stream.flush();
}
}

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

    QFile diagnosticFile;
    if (app.arguments().contains(QStringLiteral("--smoke-test"))) {
        const QString diagnosticPath =
            qEnvironmentVariable("FS_USER_STORIES_DIAGNOSTICS");
        if (!diagnosticPath.isEmpty()) {
            diagnosticFile.setFileName(diagnosticPath);
            if (diagnosticFile.open(QIODevice::WriteOnly | QIODevice::Truncate |
                                    QIODevice::Text)) {
                gDiagnosticFile = &diagnosticFile;
                qInstallMessageHandler(diagnosticMessageHandler);
            }
        }
    }

    // macOS-flavoured palette. Even on Windows/Linux the app reads closer to
    // the macOS reference screenshot. macOS-style colours:
    //   * Window / Base: very light grey/white (#f5f5f7 / #ffffff)
    //   * Text: near-black (#1d1d1f)
    //   * Highlight: Apple blue (#0a84ff, the macOS 11+ accent)
    //   * HighlightedText: white
    //   * Mid (dividers, borders): #d1d1d6
    {
        QPalette mac;
        mac.setColor(QPalette::Window,        QColor(0xf5, 0xf5, 0xf7));
        mac.setColor(QPalette::WindowText,    QColor(0x1d, 0x1d, 0x1f));
        mac.setColor(QPalette::Base,          QColor(0xff, 0xff, 0xff));
        mac.setColor(QPalette::AlternateBase, QColor(0xf5, 0xf5, 0xf7));
        mac.setColor(QPalette::ToolTipBase,    QColor(0xff, 0xff, 0xff));
        mac.setColor(QPalette::ToolTipText,    QColor(0x1d, 0x1d, 0x1f));
        mac.setColor(QPalette::Text,           QColor(0x1d, 0x1d, 0x1f));
        mac.setColor(QPalette::Button,        QColor(0xff, 0xff, 0xff));
        mac.setColor(QPalette::ButtonText,    QColor(0x1d, 0x1d, 0x1f));
        mac.setColor(QPalette::Highlight,      QColor(0x0a, 0x84, 0xff));
        mac.setColor(QPalette::HighlightedText,QColor(0xff, 0xff, 0xff));
        mac.setColor(QPalette::Mid,           QColor(0xd1, 0xd1, 0xd6));
        mac.setColor(QPalette::Light,         QColor(0xf5, 0xf5, 0xf7));
        mac.setColor(QPalette::Dark,          QColor(0x6e, 0x6e, 0x73));
        mac.setColor(QPalette::PlaceholderText,QColor(0xa1, 0xa1, 0xa6));
        app.setPalette(mac);
    }

    // Default font for the app. We deliberately do NOT set a specific family
    // on macOS (Apple's SF Pro is proprietary and not redistributable).
    // Instead we let the OS pick its native UI font:
    //   * macOS: system default (SF Pro / system-ui, owned by the user)
    //   * Windows: Segoe UI Variable (substitutable via QFontDatabase)
    //   * Linux: distribution default (Ubuntu, Cantarell, ...)
    // We only set the family on Windows where Segoe UI Variable is bundled
    // with the OS and gives a clean macOS-like variable look.
    {
        QFont uiFont = app.font();
        uiFont.setStyleHint(QFont::SansSerif);
#ifdef Q_OS_WIN
        uiFont.setFamily(QStringLiteral("Segoe UI Variable"));
#endif
#ifdef Q_OS_LINUX
        uiFont.setPointSize(10);
#endif
        app.setFont(uiFont);
    }

    // Load Material Symbols Outlined (OFL-licensed, OFL file bundled at
    // <bindir>/resources/fonts/MaterialSymbolsOutlined-Variable.woff2 by the
    // POST_BUILD step in CMakeLists). Returns the family name to use in QML.
    QString iconFontFamily = QStringLiteral("Material Symbols Outlined");
    const QString fontPath =
        QCoreApplication::applicationDirPath() +
        QStringLiteral("/resources/fonts/MaterialSymbolsOutlined-Variable.ttf");
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
        qCritical() << "QML did not create the application window";
        return 1;
    }

    // CI launches the fully staged application with this flag. Reaching this
    // point proves that Windows loaded the executable and its runtime DLLs,
    // the QML module was found, and Component.onCompleted reached the Rust
    // core-backed workspace load without reporting an error.
    if (app.arguments().contains(QStringLiteral("--smoke-test"))) {
        if (!controller.lastError().isEmpty()) {
            qCritical().noquote() << "Smoke test failed:" << controller.lastError();
            return 2;
        }

        // Exercise the same controller methods used by the QML buttons. This
        // catches packaged-core failures that a window-only smoke test misses.
        controller.createProject(QStringLiteral("Windows package smoke test"),
                                 QStringLiteral("SMK"));
        if (!controller.lastError().isEmpty() || controller.projects().isEmpty()) {
            qCritical().noquote() << "Create-project smoke test failed:"
                                  << controller.lastError();
            return 3;
        }
        const QString projectId =
            controller.projects().constLast().toMap().value("id").toString();
        controller.openProject(projectId);
        controller.createStory(QStringLiteral("Packaged application opens"),
                               QStringLiteral("tester"),
                               QStringLiteral("exercise the Windows build"),
                               QStringLiteral("distribution failures are caught"));
        if (!controller.lastError().isEmpty()) {
            qCritical().noquote() << "Create-story smoke test failed:"
                                  << controller.lastError();
            return 4;
        }
        controller.deleteProject(projectId);
        if (!controller.lastError().isEmpty()) {
            qCritical().noquote() << "Delete-project smoke test failed:"
                                  << controller.lastError();
            return 5;
        }
        qInfo() << "Windows bundle smoke test passed";
        return 0;
    }

    // workspace.projects is populated by QML's own Component.onCompleted;
    // main.cpp no longer needs to call controller.load() here.
    return app.exec();
}
