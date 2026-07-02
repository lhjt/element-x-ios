//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

nonisolated struct NotificationExtensionPresencePolicy: Sendable {
    static let foregroundActiveMaximumAge: TimeInterval = 30
    static let foregroundActiveRefreshInterval = foregroundActiveMaximumAge / 2
    
    let sharePresence: Bool
    let mainAppActivityStateSnapshot: MainAppActivityStateSnapshot
    
    init(sharePresence: Bool, mainAppActivityStateSnapshot: MainAppActivityStateSnapshot) {
        self.sharePresence = sharePresence
        self.mainAppActivityStateSnapshot = mainAppActivityStateSnapshot
    }
    
    init(appSettings: CommonSettingsProtocol) {
        self.init(sharePresence: appSettings.sharePresence,
                  mainAppActivityStateSnapshot: appSettings.mainAppActivityStateSnapshot)
    }
    
    func shouldForceOfflinePresence(currentSystemUptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard sharePresence else {
            return true
        }
        
        guard mainAppActivityStateSnapshot.state == .foregroundActive,
              let lastUpdatedSystemUptime = mainAppActivityStateSnapshot.lastUpdatedSystemUptime,
              currentSystemUptime >= lastUpdatedSystemUptime else {
            return true
        }
        
        return currentSystemUptime - lastUpdatedSystemUptime > Self.foregroundActiveMaximumAge
    }
}
