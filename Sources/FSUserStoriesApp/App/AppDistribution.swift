// SPDX-License-Identifier: MIT

import Foundation

/// Distribution-specific behaviour is deliberately limited to platform
/// constraints. Product features remain the same in the direct and App Store
/// builds.
enum AppDistribution {
    static var isMacAppStore: Bool {
        isMacAppStore(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    static func isMacAppStore(infoDictionary: [String: Any]) -> Bool {
        let channel = (infoDictionary["FSDistributionChannel"] as? String)?
            .lowercased()
            .filter(\.isLetter)
        return channel == "appstore"
    }
}
