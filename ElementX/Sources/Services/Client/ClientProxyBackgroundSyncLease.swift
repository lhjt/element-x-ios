//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import Synchronization

final nonisolated class ClientProxyBackgroundSyncLease: ClientProxyBackgroundSyncLeaseProtocol {
    private let id: UUID
    private let releaseAction: @MainActor @Sendable (UUID) async -> Void
    private let hasReleased = Mutex(false)
    
    init(id: UUID, releaseAction: @escaping @MainActor @Sendable (UUID) async -> Void) {
        self.id = id
        self.releaseAction = releaseAction
    }
    
    deinit {
        guard markReleased() else { return }
        
        Task { [releaseAction, id] in
            await releaseAction(id)
        }
    }
    
    func release() async {
        guard markReleased() else { return }
        
        await releaseAction(id)
    }
    
    private func markReleased() -> Bool {
        hasReleased.withLock { hasReleased in
            guard !hasReleased else {
                return false
            }
            
            hasReleased = true
            return true
        }
    }
}
