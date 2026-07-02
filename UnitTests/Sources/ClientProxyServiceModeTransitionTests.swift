//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Testing

@MainActor
struct ClientProxyServiceModeTransitionTests {
    @Test
    func backgroundGraceModeUpdatePreservesRunningAndSuspendedState() async throws {
        let runningHarness = try await ClientProxyPresenceHarness()
        await runningHarness.proxy.resumeServices(mode: .foregroundActive)
        runningHarness.operations.removeAll()
        
        await runningHarness.proxy.updateServiceMode(.backgroundGrace)
        
        #expect(runningHarness.syncService.startCallsCount == 1)
        #expect(runningHarness.operations == [.presence(.unavailable, true)])
        
        let suspendedHarness = try await ClientProxyPresenceHarness()
        await suspendedHarness.proxy.updateServiceMode(.backgroundGrace)
        
        #expect(!suspendedHarness.syncService.startCalled)
        #expect(suspendedHarness.operations == [.presence(.unavailable, true)])
        
        let suspendedResumeHarness = try await ClientProxyPresenceHarness()
        await suspendedResumeHarness.proxy.resumeServices(mode: .backgroundGrace)
        
        #expect(!suspendedResumeHarness.syncService.startCalled)
        #expect(suspendedResumeHarness.operations == [.presence(.unavailable, true)])
    }
    
    @Test
    func backgroundGraceModeUpdatePreservesInFlightForegroundResumeIntent() async throws {
        let harness = try await ClientProxyPresenceHarness()
        let (finishStart, finishStartContinuation) = AsyncStream<Void>.makeStream()
        harness.blockSyncStart(until: finishStart)
        
        let syncStarted = harness.fulfillment(for: .syncStart)
        let resumeTask = Task {
            await harness.proxy.resumeServices(mode: .foregroundActive)
        }
        try await syncStarted.fulfill()
        
        let modeUpdateTask = Task {
            await harness.proxy.updateServiceMode(.backgroundGrace)
        }
        finishStartContinuation.yield(())
        finishStartContinuation.finish()
        
        await resumeTask.value
        await modeUpdateTask.value
        
        #expect(harness.syncService.startCallsCount == 1)
        #expect(!harness.syncService.stopCalled)
        #expect(harness.operations == [.presence(.online, false), .clientResume, .syncStart, .presence(.unavailable, true)])
    }
    
    @Test
    func pauseAndTerminationModePauseSendImmediately() async throws {
        let harness = try await ClientProxyPresenceHarness()
        
        await harness.proxy.resumeServices(mode: .foregroundActive)
        harness.operations.removeAll()
        await harness.proxy.pauseServices(mode: .backgroundGrace)
        
        #expect(harness.client.setPresencePresenceImmediateReceivedInvocations.last?.presence == .unavailable)
        #expect(harness.client.setPresencePresenceImmediateReceivedInvocations.last?.immediate == true)
        #expect(harness.operations.first == .syncStop)
        #expect(harness.operations.last == .presence(.unavailable, true))
    }
    
    @Test
    func pauseStopsSyncBeforeWaitingForPresence() async throws {
        let harness = try await ClientProxyPresenceHarness()
        await harness.proxy.resumeServices(mode: .foregroundActive)
        harness.operations.removeAll()
        
        let (finishPresence, finishPresenceContinuation) = AsyncStream<Void>.makeStream()
        harness.blockPresence(until: finishPresence)
        
        let syncStopped = harness.fulfillment(for: .syncStop)
        let pauseTask = Task {
            await harness.proxy.pauseServices(mode: .backgroundGrace)
        }
        try await syncStopped.fulfill()
        
        #expect(harness.operations.first == .syncStop)
        
        finishPresenceContinuation.yield(())
        finishPresenceContinuation.finish()
        await pauseTask.value
        
        #expect(harness.operations.first == .syncStop)
        #expect(harness.operations.last == .presence(.unavailable, true))
    }
    
    @Test
    func foregroundResumeWinsOverDelayedBackgroundPause() async throws {
        let harness = try await ClientProxyPresenceHarness()
        await harness.proxy.resumeServices(mode: .foregroundActive)
        
        let (finishStop, finishStopContinuation) = AsyncStream<Void>.makeStream()
        harness.blockSyncStop(until: finishStop)
        
        let syncStopped = harness.fulfillment(for: .syncStop)
        let pauseTask = Task {
            await harness.proxy.pauseServices(mode: .backgroundGrace)
        }
        try await syncStopped.fulfill()
        let resumeTask = Task {
            await harness.proxy.resumeServices(mode: .foregroundActive)
        }
        finishStopContinuation.yield(())
        finishStopContinuation.finish()
        
        await pauseTask.value
        await resumeTask.value
        
        #expect(harness.client.setPresencePresenceImmediateReceivedInvocations.last?.presence == .online)
        #expect(harness.operations.last == .syncStart)
    }
}
