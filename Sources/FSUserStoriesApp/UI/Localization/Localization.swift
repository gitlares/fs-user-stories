// SPDX-License-Identifier: MIT

import Foundation

enum L10n {
    private static let bundle: Bundle = {
        let arguments = ProcessInfo.processInfo.arguments
        guard
            let flagIndex = arguments.firstIndex(of: "--language"),
            arguments.indices.contains(flagIndex + 1),
            let path = AppResources.bundle.path(
                forResource: arguments[flagIndex + 1],
                ofType: "lproj"
            ),
            let localizedBundle = Bundle(path: path)
        else {
            return AppResources.bundle
        }

        return localizedBundle
    }()

    static func string(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    static func storyCount(_ count: Int) -> String {
        let key = count == 1 ? "story.count.one" : "story.count.other"
        return String(format: string(key), locale: .current, count)
    }

    static func criterionProgress(met: Int, total: Int) -> String {
        let key = total == 1 ? "criterion.progress.one" : "criterion.progress.other"
        return String(format: string(key), locale: .current, met, total)
    }
}
