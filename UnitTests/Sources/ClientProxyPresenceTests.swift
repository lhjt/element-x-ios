//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import MatrixRustSDK
import Testing

@MainActor
struct ClientProxyPresenceTests {
    @Test
    func foregroundActiveResumeWithSharingOnSendsOnlineBeforeSyncStart() async throws {
        let harness = try await ClientProxyPresenceHarness()
        
        await harness.proxy.resumeServices(mode: .foregroundActive)
        
        #expect(harness.client.setPresencePresenceImmediateReceivedInvocations.map(\.presence) == [.online])
        #expect(harness.client.setPresencePresenceImmediateReceivedInvocations.map(\.immediate) == [false])
        #expect(harness.operations.prefix(3) == [.presence(.online, false), .clientResume, .syncStart])
    }
    
    @Test
    func foregroundActiveResumeWithSharingOffSendsOfflineAndNeverOnline() async throws {
        let harness = try await ClientProxyPresenceHarness(sharePresence: false)
        
        await harness.proxy.resumeServices(mode: .foregroundActive)
        
        #expect(harness.client.setPresencePresenceImmediateReceivedInvocations.map(\.presence) == [.offline])
        #expect(harness.client.setPresencePresenceImmediateReceivedInvocations.map(\.immediate) == [false])
        #expect(!harness.client.setPresencePresenceImmediateReceivedInvocations.map(\.presence).contains(.online))
    }
    
    @Test
    func foregroundActiveResumeIntentSurvivesUnreachableNetwork() async throws {
        let harness = try await ClientProxyPresenceHarness(networkReachability: .unreachable)
        
        await harness.proxy.resumeServices(mode: .foregroundActive)
        
        #expect(harness.operations.isEmpty)
        
        let syncStarted = harness.fulfillment(for: .syncStart)
        harness.networkReachabilitySubject.send(.reachable)
        try await syncStarted.fulfill()
        
        #expect(harness.operations.prefix(3) == [.presence(.online, false), .clientResume, .syncStart])
    }
    
    @Test
    func queuedReconcileDoesNotStartSyncWhileNetworkUnreachable() async throws {
        let harness = try await ClientProxyPresenceHarness(networkReachability: .unreachable)
        
        await harness.proxy.resumeServices(mode: .foregroundActive)
        await harness.proxy.updateServiceMode(.foregroundActive)
        
        #expect(harness.operations.isEmpty)
        
        let syncStarted = harness.fulfillment(for: .syncStart)
        harness.networkReachabilitySubject.send(.reachable)
        try await syncStarted.fulfill()
        
        #expect(harness.operations.prefix(3) == [.presence(.online, false), .clientResume, .syncStart])
    }
    
    @Test
    func backgroundGraceModeUpdateAfterUnreachableForegroundIntentDoesNotStartSync() async throws {
        let harness = try await ClientProxyPresenceHarness(networkReachability: .unreachable)
        
        await harness.proxy.resumeServices(mode: .foregroundActive)
        await harness.proxy.updateServiceMode(.backgroundGrace)
        
        #expect(!harness.syncService.startCalled)
        #expect(harness.operations == [.presence(.unavailable, true)])
    }
    
    @Test
    func backgroundGraceIdleSendsExpectedPresence() async throws {
        for (sharePresence, expectedPresence) in [(true, PresenceState.unavailable), (false, .offline)] {
            let harness = try await ClientProxyPresenceHarness(sharePresence: sharePresence)
            
            await harness.proxy.updateServiceMode(.backgroundGrace)
            
            #expect(harness.client.setPresencePresenceImmediateReceivedInvocations.map(\.presence) == [expectedPresence])
            #expect(harness.client.setPresencePresenceImmediateReceivedInvocations.map(\.immediate) == [true])
            #expect(!harness.syncService.startCalled)
        }
    }
    
    @Test
    func backgroundRefreshSendsOfflineImmediatelyBeforeSyncStart() async throws {
        let harness = try await ClientProxyPresenceHarness()
        
        await harness.proxy.resumeServices(mode: .backgroundSync)
        
        #expect(harness.client.setPresencePresenceImmediateReceivedInvocations.map(\.presence) == [.offline])
        #expect(harness.client.setPresencePresenceImmediateReceivedInvocations.map(\.immediate) == [true])
        #expect(harness.operations.prefix(3) == [.presence(.offline, true), .clientResume, .syncStart])
    }
}
