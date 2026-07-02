//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Testing

@MainActor
struct ClientProxyBackgroundSyncLeaseTests {
    @Test
    func backgroundSyncLeasesPauseOnlyAfterLastRelease() async throws {
        let harness = try await ClientProxyPresenceHarness()
        
        let firstLease = await harness.proxy.acquireBackgroundSyncLease()
        
        #expect(harness.operations.prefix(3) == [.presence(.offline, true), .clientResume, .syncStart])
        harness.operations.removeAll()
        
        let secondLease = await harness.proxy.acquireBackgroundSyncLease()
        
        #expect(harness.operations.isEmpty)
        
        await firstLease.release()
        
        #expect(harness.operations.isEmpty)
        
        await secondLease.release()
        
        #expect(harness.operations.first == .syncStop)
        #expect(harness.operations.last == .presence(.unavailable, true))
    }
    
    @Test
    func backgroundSyncLeaseReleaseAfterBackgroundGraceModeUpdatePausesSync() async throws {
        let harness = try await ClientProxyPresenceHarness()
        let lease = await harness.proxy.acquireBackgroundSyncLease()
        harness.operations.removeAll()
        
        await harness.proxy.updateServiceMode(.backgroundGrace)
        
        #expect(harness.operations == [.presence(.unavailable, true)])
        harness.operations.removeAll()
        
        await lease.release()
        
        #expect(harness.syncService.stopCalled)
        #expect(harness.operations.first == .syncStop)
        #expect(harness.operations.last == .presence(.unavailable, true))
    }
    
    @Test
    func backgroundSyncLeaseReleaseDoesNotPauseForegroundSync() async throws {
        let harness = try await ClientProxyPresenceHarness()
        let lease = await harness.proxy.acquireBackgroundSyncLease()
        harness.operations.removeAll()
        
        await harness.proxy.resumeServices(mode: .foregroundActive)
        
        #expect(harness.operations == [.presence(.online, false)])
        harness.operations.removeAll()
        
        await lease.release()
        
        #expect(harness.operations.isEmpty)
        #expect(!harness.syncService.stopCalled)
    }
}
