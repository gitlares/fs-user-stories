// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)

        // Swift Package executable targets are launched by Xcode as plain Unix
        // executables instead of an application bundle, so AppKit cannot read
        // CFBundleIconFile from Support/Info.plist while developing. Keep the
        // correct application identity in the Dock and app switcher in both the
        // package-run and packaged .app paths.
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }

        DispatchQueue.main.async {
            NSApplication.shared.activate()
            for window in NSApplication.shared.windows where window.canBecomeMain {
                window.deminiaturize(nil)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}

@main
struct FSUserStoriesApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
    @AppStorage("menuBarExtraVisible") private var menuBarExtraVisible = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: AppStore

    init() {
        let usesPreviewData = ProcessInfo.processInfo.arguments.contains("--preview-data")
        if usesPreviewData {
            _store = State(initialValue: .preview)
        } else {
            do {
                _store = State(initialValue: try .persistent())
            } catch {
                fatalError("Unable to open the local database: \(error.localizedDescription)")
            }
        }
    }

    var body: some Scene {
        // The workspace is intentionally a single window. Menu-bar actions must
        // reveal this window, never create a second workspace instance.
        Window("FS User Stories", id: "workspace") {
            WorkspaceView(store: store)
                .frame(minWidth: 980, minHeight: 640)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    store.applicationDidBecomeActive()
                }
        }
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .commands {
            StoryCommands(store: store)
        }

        Window(L10n.string("MCP Connection"), id: "mcp-connection") {
            MCPConnectionView(store: store)
                .frame(minWidth: 680, minHeight: 620)
        }
        .defaultSize(width: 760, height: 760)
        .windowResizability(.contentMinSize)

        MenuBarExtra(
            "FS User Stories",
            systemImage: "checkmark.square",
            isInserted: $menuBarExtraVisible
        ) {
            MenuBarView(store: store)
        }
        .menuBarExtraStyle(.menu)
    }
}
