//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import UIKit

enum AppCoordinatorClientServiceModeRequest {
    case appRoute
    case inlineReply
    case manualBackgroundWork
    case restoredSession(hasPendingStoredInlineReply: Bool)
}

enum AppCoordinatorClientServiceModeResolver {
    static func resumeMode(for request: AppCoordinatorClientServiceModeRequest, appState: UIApplication.State) -> ClientServiceRunMode {
        switch request {
        case .appRoute:
            activeOrBackgroundGraceMode(appState: appState)
        case .inlineReply, .manualBackgroundWork:
            activeOrBackgroundSyncMode(appState: appState)
        case .restoredSession(let hasPendingStoredInlineReply):
            if appState == .active {
                .foregroundActive
            } else {
                hasPendingStoredInlineReply ? .backgroundSync : .backgroundGrace
            }
        }
    }
    
    static func backgroundEnteredModeUpdate() -> ClientServiceRunMode {
        .backgroundGrace
    }
    
    static func inactiveModeUpdate() -> ClientServiceRunMode {
        .backgroundGrace
    }
    
    static func foregroundEnteredAction() -> ClientServiceRunMode? {
        nil
    }
    
    static func activeForegroundResumeMode() -> ClientServiceRunMode {
        .foregroundActive
    }
    
    static func backgroundRefreshResumeMode() -> ClientServiceRunMode {
        .backgroundSync
    }
    
    static func backgroundPauseMode() -> ClientServiceRunMode {
        .backgroundGrace
    }
    
    private static func activeOrBackgroundGraceMode(appState: UIApplication.State) -> ClientServiceRunMode {
        appState == .active ? .foregroundActive : .backgroundGrace
    }
    
    private static func activeOrBackgroundSyncMode(appState: UIApplication.State) -> ClientServiceRunMode {
        appState == .active ? .foregroundActive : .backgroundSync
    }
}

extension UIApplication.State {
    var mainAppActivityState: MainAppActivityState {
        switch self {
        case .active:
            .foregroundActive
        case .inactive:
            .inactive
        case .background:
            .background
        @unknown default:
            .inactive
        }
    }
}
