import AppKit
import Foundation

enum AppReleaseInfo {
    static let shortVersion = value(for: "CFBundleShortVersionString", fallback: "Development")
    static let build = value(for: "CFBundleVersion", fallback: "Local")
    static let releaseName = value(for: "FSReleaseName", fallback: "Development Build")

    static var displayVersion: String {
        "\(shortVersion) — \(releaseName) (Build \(build))"
    }

    @MainActor
    static func presentAboutPanel() {
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationVersion: "\(shortVersion) — \(releaseName)",
            .version: "Build \(build)"
        ])
        NSApplication.shared.activate()
    }

    private static func value(for key: String, fallback: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? fallback
    }
}
