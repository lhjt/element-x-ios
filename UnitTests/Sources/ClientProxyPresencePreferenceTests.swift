//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Testing

@MainActor
struct ClientProxyPresencePreferenceTests {
    @Test
    func turningSharingOffSendsOfflineImmediately() async throws {
        let harness = try await ClientProxyPresenceHarness()
        await harness.proxy.resumeServices(mode: .foregroundActive)
        
        let offlinePresence = harness.fulfillment(for: .presence(.offline, true))
        harness.appSettings.sharePresence = false
        try await offlinePresence.fulfill()
        
        #expect(harness.client.setPresencePresenceImmediateReceivedInvocations.map(\.presence) == [.online, .offline])
        #expect(harness.client.setPresencePresenceImmediateReceivedInvocations.map(\.immediate) == [false, true])
    }
    
    @Test
    func turningSharingOnPromotesOnlineOnlyFromRunningForegroundActive() async throws {
        let foregroundHarness = try await ClientProxyPresenceHarness(sharePresence: false)
        await foregroundHarness.proxy.resumeServices(mode: .foregroundActive)
        
        let onlinePresence = foregroundHarness.fulfillment(for: .presence(.online, false))
        foregroundHarness.appSettings.sharePresence = true
        try await onlinePresence.fulfill()
        
        #expect(foregroundHarness.client.setPresencePresenceImmediateReceivedInvocations.map(\.presence) == [.offline, .online])
        #expect(foregroundHarness.client.setPresencePresenceImmediateReceivedInvocations.map(\.immediate) == [false, false])
        
        let backgroundHarness = try await ClientProxyPresenceHarness(sharePresence: false)
        await backgroundHarness.proxy.resumeServices(mode: .backgroundSync)
        
        let backgroundOfflinePresence = backgroundHarness.fulfillment(for: .presence(.offline, true))
        backgroundHarness.appSettings.sharePresence = true
        try await backgroundOfflinePresence.fulfill()
        
        #expect(backgroundHarness.client.setPresencePresenceImmediateReceivedInvocations.map(\.presence) == [.offline, .offline])
        #expect(!backgroundHarness.client.setPresencePresenceImmediateReceivedInvocations.map(\.presence).contains(.online))
    }
}
