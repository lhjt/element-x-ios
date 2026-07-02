//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Testing

@MainActor
struct ClientProxySyncRestartTests {
    @Test
    func restartAfterSyncErrorPreservesLastRequestedRunMode() async throws {
        let harness = try await ClientProxyPresenceHarness()
        await harness.proxy.resumeServices(mode: .backgroundSync)
        
        let restartStarted = harness.fulfillment(for: .syncStart)
        harness.syncService.stateListenerReceivedListener?.onUpdate(state: .error)
        try await restartStarted.fulfill()
        
        #expect(Array(harness.client.setPresencePresenceImmediateReceivedInvocations.map(\.presence).suffix(2)) == [.offline, .offline])
        #expect(Array(harness.client.setPresencePresenceImmediateReceivedInvocations.map(\.immediate).suffix(2)) == [true, true])
        #expect(harness.syncService.startCallsCount == 2)
        #expect(!harness.client.setPresencePresenceImmediateReceivedInvocations.map(\.presence).contains(.online))
    }
    
    @Test
    func pauseCancelsDelayedRestartAfterSyncError() async throws {
        let harness = try await ClientProxyPresenceHarness(restartServicesDelay: .seconds(60))
        await harness.proxy.resumeServices(mode: .backgroundSync)
        harness.operations.removeAll()
        
        harness.syncService.stateListenerReceivedListener?.onUpdate(state: .error)
        await harness.proxy.pauseServices(mode: .backgroundGrace)
        
        #expect(harness.syncService.startCallsCount == 1)
        #expect(harness.operations.first == .syncStop)
        #expect(harness.operations.last == .presence(.unavailable, true))
    }
}
