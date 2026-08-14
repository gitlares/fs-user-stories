import AppKit
import Foundation

enum AppResources {
    private static let resourceBundleName = "FSUserStories_FSUserStoriesApp.bundle"

    static let bundle: Bundle = {
        var candidates: [URL] = []

        func appendAncestorCandidates(startingAt initialDirectory: URL) {
            var directory = initialDirectory
            for _ in 0..<6 {
                candidates.append(
                    directory.appendingPathComponent(resourceBundleName, isDirectory: true)
                )
                directory.deleteLastPathComponent()
            }
        }

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(
                resourceURL.appendingPathComponent(resourceBundleName, isDirectory: true)
            )
        }

        candidates.append(
            Bundle.main.bundleURL.appendingPathComponent(resourceBundleName, isDirectory: true)
        )

        if let executableURL = Bundle.main.executableURL {
            appendAncestorCandidates(startingAt: executableURL.deletingLastPathComponent())
        }

        // XCTest is hosted by Apple's test runner, so Bundle.main may point to
        // xctest rather than the package product. Its loaded test bundle still
        // gives us a stable path back to SwiftPM's sibling resource bundle.
        for loadedBundle in Bundle.allBundles where loadedBundle != .main {
            appendAncestorCandidates(startingAt: loadedBundle.bundleURL)
        }

        for candidate in candidates {
            if let bundle = Bundle(url: candidate) {
                return bundle
            }
        }

        // Missing optional resources must never make the application crash at
        // launch. Callers already handle absent individual files gracefully.
        return .main
    }()

    static func menuBarIcon(darkAppearance: Bool) -> NSImage {
        let resourceName = darkAppearance ? "MenuBarIconDark" : "MenuBarIconLight"
        let image = bundle.url(forResource: resourceName, withExtension: "png")
            .flatMap(NSImage.init(contentsOf:))
            ?? NSImage(systemSymbolName: "checkmark.square", accessibilityDescription: nil)
            ?? NSImage()
        image.isTemplate = false
        image.size = NSSize(width: 21, height: 16)
        return image
    }
}
