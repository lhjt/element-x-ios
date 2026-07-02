//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import MatrixRustSDK

enum ClientPresence {
    case online
    case unavailable
    case offline
    
    var rustValue: PresenceState {
        switch self {
        case .online:
            .online
        case .unavailable:
            .unavailable
        case .offline:
            .offline
        }
    }
}

struct PresenceUpdate {
    let presence: ClientPresence
    let sendImmediately: Bool
}

enum ServiceState: Equatable {
    case running(ClientServiceRunMode)
    case suspended(ClientServiceRunMode)
    
    var isRunning: Bool {
        switch self {
        case .running:
            true
        case .suspended:
            false
        }
    }
    
    var isRunningInBackground: Bool {
        switch self {
        case .running(.backgroundGrace), .running(.backgroundSync):
            true
        case .running(.foregroundActive), .suspended:
            false
        }
    }
    
    var runMode: ClientServiceRunMode {
        switch self {
        case .running(let mode), .suspended(let mode):
            mode
        }
    }
    
    func withRunMode(_ mode: ClientServiceRunMode) -> ServiceState {
        switch self {
        case .running:
            .running(mode)
        case .suspended:
            .suspended(mode)
        }
    }
    
    func presenceUpdate(sharePresence: Bool, forceImmediate: Bool) -> PresenceUpdate {
        let update: PresenceUpdate
        
        switch (self, sharePresence) {
        case (.running(.foregroundActive), true):
            update = .init(presence: .online, sendImmediately: false)
        case (.running(.foregroundActive), false):
            update = .init(presence: .offline, sendImmediately: false)
        case (.running(.backgroundSync), _):
            update = .init(presence: .offline, sendImmediately: true)
        case (_, true):
            update = .init(presence: .unavailable, sendImmediately: true)
        case (_, false):
            update = .init(presence: .offline, sendImmediately: true)
        }
        
        guard forceImmediate else {
            return update
        }
        
        return .init(presence: update.presence, sendImmediately: true)
    }
}
