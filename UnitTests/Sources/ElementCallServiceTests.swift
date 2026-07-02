//
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import CallKit
import Clocks
@testable import ElementX
import MatrixRustSDKMocks
import PushKit
import Testing
import UIKit

@MainActor
final class ElementCallServiceTests {
    private var callProvider: CXProviderMock!
    private var currentDate: Date!
    private var testClock: TestClock<Duration>!
    private var pushRegistry: PKPushRegistry!
    private var service: ElementCallService!
    private var clientProxy: ClientProxyMock!
    
    init() {
        pushRegistry = PKPushRegistry(queue: nil)
        callProvider = CXProviderMock(.init())
        currentDate = Date()
        testClock = TestClock()
        clientProxy = ClientProxyMock(.init())
        let dateProvider: () -> Date = {
            self.currentDate
        }
        service = ElementCallService(callProvider: callProvider, timeProvider: TimeProvider(clock: testClock, now: dateProvider))
    }
    
    isolated deinit {
        callProvider = nil
        currentDate = nil
        testClock = nil
        pushRegistry = nil
        clientProxy = nil
    }
    
    @Test
    func incomingCall() async {
        #expect(!callProvider.reportNewIncomingCallWithUpdateCompletionCalled)
        
        await waitForConfirmation { confirmation in
            let pkPushPayloadMock = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
            
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: pkPushPayloadMock, for: .voIP) {
                confirmation()
            }
        }
        
        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionCalled)
        // Verify the provider was called with a CXCallUpdate that has video enabled
        if let args = callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments {
            #expect(args.update.hasVideo == true)
        } else {
            Issue.record("Expected reportNewIncomingCallWithUpdateCompletionReceivedArguments to be captured")
        }
    }
    
    @Test
    func incomingVoiceCall() async {
        #expect(!callProvider.reportNewIncomingCallWithUpdateCompletionCalled)
        
        await waitForConfirmation { confirmation in
            let pkPushPayloadMock = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
                .updateIsVoice(true)
            
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: pkPushPayloadMock, for: .voIP) {
                confirmation()
            }
        }
        
        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionCalled)
        // Verify the provider was called with a CXCallUpdate that has video enabled
        if let args = callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments {
            // Due to a limitation on Callkit and Webviews, we currently have to report voice calls as having video,
            // even if they are voice calls :/ If not the webview is not started and the call is not shown to the user.
            #expect(args.update.hasVideo == true)
        } else {
            Issue.record("Expected reportNewIncomingCallWithUpdateCompletionReceivedArguments to be captured")
        }
    }
    
    @Test(.disabled())
    func callIsTimingOut() async {
        #expect(!callProvider.reportNewIncomingCallWithUpdateCompletionCalled)
        
        await confirmation { confirmation in
            let pushPayload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 20)
            
            service.pushRegistry(pushRegistry,
                                 didReceiveIncomingPushWith: pushPayload,
                                 for: .voIP) {
                confirmation()
            }
        }
        
        await confirmation { confirmation in
            callProvider.reportCallWithEndedAtReasonClosure = { _, _, reason in
                if reason == .unanswered {
                    confirmation()
                } else {
                    Issue.record("Call should have ended as unanswered")
                }
            }
            
            // advance past the timeout
            await testClock.advance(by: .seconds(30))
        }
    }
    
    @Test
    func lifetimeIsCapped() async {
        #expect(!callProvider.reportNewIncomingCallWithUpdateCompletionCalled)
        
        let pushPayload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 300)
        service.pushRegistry(pushRegistry,
                             didReceiveIncomingPushWith: pushPayload,
                             for: .voIP) { }
        
        await expectUnansweredTimeoutScheduled()
        await testClock.advance(by: .seconds(100))
        
        let unansweredCount = callProvider.reportCallWithEndedAtReasonReceivedInvocations.filter { $0.reason == .unanswered }.count
        #expect(unansweredCount == 1)
    }
    
    @Test
    func callIntentRawValues() {
        // Test to ensure that the implicit rawValue of the string enum matches the MSC values
        #expect(CallIntent.audio.rawValue == "audio")
        #expect(CallIntent.video.rawValue == "video")
    }
    
    @Test
    func timeoutClearsIncomingCallStateBeforeNextPush() async {
        let firstPayload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 60)
        service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: firstPayload, for: .voIP) { }
        
        await expectUnansweredTimeoutScheduled()
        let firstCallUUID = callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments?.uuid
        
        await testClock.advance(by: .seconds(70))
        
        // Send push #2 for the same room; the previous incoming state must be cleared,
        // so the second push gets a fresh CallID.
        await waitForConfirmation { confirmation in
            let secondPayload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 60)
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: secondPayload, for: .voIP) {
                confirmation()
            }
        }
        
        let secondCallUUID = callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments?.uuid
        
        #expect(firstCallUUID != nil)
        #expect(secondCallUUID != nil)
        #expect(firstCallUUID != secondCallUUID)
        
        let unansweredCount = callProvider.reportCallWithEndedAtReasonReceivedInvocations.filter { $0.reason == .unanswered }.count
        #expect(unansweredCount == 1)
    }
    
    @Test
    func setupCallSessionCancelsPendingUnansweredTimeout() async {
        // Schedule the 60s unanswered timer via an incoming push
        await waitForConfirmation { confirmation in
            let payload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 60)
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) {
                confirmation()
            }
        }
        
        // Simulate the answer flow handing off to setupCallSession, which must cancel
        // the pending endUnansweredCallTask as part of clearing the incoming state.
        await expectUnansweredTimeoutScheduled()
        await service.setupCallSession(roomID: "!room:example.com", roomDisplayName: "welcome")
        await expectNoUnansweredTimeoutScheduled()
        
        // Advance past what would have been the 60s unanswered timeout
        await testClock.advance(by: .seconds(120))
        
        let unansweredCount = callProvider.reportCallWithEndedAtReasonReceivedInvocations.filter { $0.reason == .unanswered }.count
        #expect(unansweredCount == 0, "endUnansweredCallTask should have been cancelled by setupCallSession")
    }
    
    @Test
    func expiredPushReportsMissedCall() async {
        // An expired push is a real call we missed, so it should show up in Recents as one.
        let pushPayload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 20)
        currentDate = currentDate.addingTimeInterval(60)
        await expectImmediatelyEndedCallReported(forPayload: pushPayload, expectedReason: .unanswered)
        
        let update = callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments?.update
        #expect(update?.localizedCallerName == "welcome")
        #expect(update?.remoteHandle?.value == "!room:example.com")
    }
    
    @Test
    func expiredPushWithClientProxyDoesNotStartIncomingCallObservation() async {
        makeService(appState: .background)
        let roomProxy = JoinedRoomProxyMock(.init(id: "!room:example.com"))
        clientProxy.roomForIdentifierClosure = { _ in .joined(roomProxy) }
        service.setClientProxy(clientProxy)
        
        let pushPayload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 20)
        currentDate = currentDate.addingTimeInterval(60)
        
        await expectImmediatelyEndedCallReported(forPayload: pushPayload, expectedReason: .unanswered)
        await yieldToScheduledObservationTasks()
        
        #expect(clientProxy.acquireBackgroundSyncLeaseCallsCount == 0)
        #expect(clientProxy.roomForIdentifierCallsCount == 0)
        #expect(roomProxy.subscribeToRoomInfoUpdatesCallsCount == 0)
        #expect(roomProxy.subscribeToCallDeclineEventsRtcNotificationEventIDListenerCallsCount == 0)
    }
    
    @Test
    func duplicateRoomPushReportsCallAsHandled() async {
        // A duplicate push for an ongoing call is reported as handled, leaving the ongoing call alone.
        await service.setupCallSession(roomID: "!room:example.com", roomDisplayName: "welcome")
        let pushPayload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
        await expectImmediatelyEndedCallReported(forPayload: pushPayload, expectedReason: .answeredElsewhere)
        
        // The call should be named so neither the brief system UI nor the Recents entry shows "Unknown".
        let update = callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments?.update
        #expect(update?.localizedCallerName == "welcome")
        
        #expect(service.ongoingCallRoomIDPublisher.value == "!room:example.com")
    }
    
    @Test
    func incomingCallObservationInBackgroundReleasesLeaseWhenStateClears() async throws {
        makeService(appState: .background)
        let roomProxy = JoinedRoomProxyMock(.init(id: "!room:example.com"))
        let backgroundSyncLeaseRecorder = BackgroundSyncLeaseRecorder()
        let events = await backgroundSyncLeaseRecorder.eventStream()
        let releaseDeferred = deferFulfillment(events) { $0 == .release(1) }
        
        clientProxy.acquireBackgroundSyncLeaseClosure = {
            await backgroundSyncLeaseRecorder.acquire()
        }
        clientProxy.roomForIdentifierClosure = { _ in .joined(roomProxy) }
        service.setClientProxy(clientProxy)
        
        await waitForConfirmation("Observe incoming call", timeout: .seconds(10)) { confirmation in
            roomProxy.subscribeToCallDeclineEventsRtcNotificationEventIDListenerClosure = { _, _ in
                confirmation()
                return .success(TaskHandleSDKMock())
            }
            
            let payload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 60)
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) { }
        }
        
        await service.setupCallSession(roomID: "!room:example.com", roomDisplayName: "welcome")
        try await releaseDeferred.fulfill()
        
        #expect(clientProxy.acquireBackgroundSyncLeaseCallsCount == 1)
        #expect(clientProxy.resumeServicesModeReceivedInvocations.isEmpty)
        #expect(clientProxy.pauseServicesModeReceivedInvocations.isEmpty)
        #expect(await backgroundSyncLeaseRecorder.recordedEvents == [.acquire(1), .release(1)])
    }
    
    @Test
    func incomingCallObservationReleasesBackgroundLeaseWhenRoomLookupFails() async throws {
        makeService(appState: .background)
        let backgroundSyncLeaseRecorder = BackgroundSyncLeaseRecorder()
        let events = await backgroundSyncLeaseRecorder.eventStream()
        let releaseDeferred = deferFulfillment(events) { $0 == .release(1) }
        
        clientProxy.acquireBackgroundSyncLeaseClosure = {
            await backgroundSyncLeaseRecorder.acquire()
        }
        clientProxy.roomForIdentifierClosure = { _ in nil }
        service.setClientProxy(clientProxy)
        
        let payload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 60)
        service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) { }
        
        try await releaseDeferred.fulfill()
        
        #expect(clientProxy.acquireBackgroundSyncLeaseCallsCount == 1)
        #expect(clientProxy.resumeServicesModeReceivedInvocations.isEmpty)
        #expect(clientProxy.pauseServicesModeReceivedInvocations.isEmpty)
        #expect(await backgroundSyncLeaseRecorder.recordedEvents == [.acquire(1), .release(1)])
    }
    
    @Test
    func staleIncomingCallObservationDoesNotReleaseNewerCallBackgroundLease() async {
        makeService(appState: .background)
        let firstRoomProxy = JoinedRoomProxyMock(.init(id: "!room:example.com"))
        let secondRoomProxy = JoinedRoomProxyMock(.init(id: "!room:example.com"))
        let roomLookupSequencer = RoomLookupSequencer()
        let backgroundSyncLeaseRecorder = BackgroundSyncLeaseRecorder()
        
        clientProxy.acquireBackgroundSyncLeaseClosure = {
            await backgroundSyncLeaseRecorder.acquire()
        }
        clientProxy.roomForIdentifierClosure = { _ in
            let lookup = await roomLookupSequencer.nextLookup()
            if lookup == .first {
                await roomLookupSequencer.waitUntilFirstLookupCanReturn()
                await roomLookupSequencer.markFirstLookupReturned()
                return .joined(firstRoomProxy)
            }
            
            return .joined(secondRoomProxy)
        }
        service.setClientProxy(clientProxy)
        
        let firstPayload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 60)
        service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: firstPayload, for: .voIP) { }
        await roomLookupSequencer.waitForFirstLookupStarted()
        await backgroundSyncLeaseRecorder.waitForEvents([.acquire(1)])
        
        await waitForConfirmation("Observe newer incoming call") { confirmation in
            secondRoomProxy.subscribeToCallDeclineEventsRtcNotificationEventIDListenerClosure = { _, _ in
                confirmation()
                return .success(TaskHandleSDKMock())
            }
            
            let secondPayload = PKPushPayloadMock()
                .updatingExpiration(currentDate, lifetime: 60)
                .updatingRTCNotificationID("$001")
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: secondPayload, for: .voIP) { }
        }
        await backgroundSyncLeaseRecorder.waitForEvents([.acquire(1), .release(1), .acquire(2)])
        
        await roomLookupSequencer.allowFirstLookupToReturn()
        await roomLookupSequencer.waitForFirstLookupReturned()
        await Task.yield()
        
        #expect(firstRoomProxy.subscribeToRoomInfoUpdatesCallsCount == 0)
        #expect(firstRoomProxy.subscribeToCallDeclineEventsRtcNotificationEventIDListenerCallsCount == 0)
        #expect(await backgroundSyncLeaseRecorder.recordedEvents == [.acquire(1), .release(1), .acquire(2)])
        
        await service.setupCallSession(roomID: "!room:example.com", roomDisplayName: "welcome")
        await backgroundSyncLeaseRecorder.waitForEvents([.acquire(1), .release(1), .acquire(2), .release(2)])
    }
    
    @Test
    func duplicateRoomPushWithClientProxyDoesNotStartIncomingCallObservation() async {
        makeService(appState: .background)
        let roomProxy = JoinedRoomProxyMock(.init(id: "!room:example.com"))
        clientProxy.roomForIdentifierClosure = { _ in .joined(roomProxy) }
        service.setClientProxy(clientProxy)
        await service.setupCallSession(roomID: "!room:example.com", roomDisplayName: "welcome")
        
        let pushPayload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 60)
        
        await expectImmediatelyEndedCallReported(forPayload: pushPayload, expectedReason: .answeredElsewhere)
        await yieldToScheduledObservationTasks()
        
        #expect(clientProxy.acquireBackgroundSyncLeaseCallsCount == 0)
        #expect(clientProxy.roomForIdentifierCallsCount == 0)
        #expect(roomProxy.subscribeToRoomInfoUpdatesCallsCount == 0)
        #expect(roomProxy.subscribeToCallDeclineEventsRtcNotificationEventIDListenerCallsCount == 0)
    }
    
    @Test
    func incomingCallObservationInForegroundDoesNotAcquireBackgroundLease() async {
        makeService(appState: .active)
        let roomProxy = JoinedRoomProxyMock(.init(id: "!room:example.com"))
        clientProxy.roomForIdentifierClosure = { _ in .joined(roomProxy) }
        service.setClientProxy(clientProxy)
        
        await waitForConfirmation("Observe incoming call", timeout: .seconds(10)) { confirmation in
            roomProxy.subscribeToCallDeclineEventsRtcNotificationEventIDListenerClosure = { _, _ in
                confirmation()
                return .success(TaskHandleSDKMock())
            }
            
            let payload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 60)
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) { }
        }
        
        #expect(clientProxy.acquireBackgroundSyncLeaseCallsCount == 0)
        #expect(clientProxy.resumeServicesModeReceivedInvocations.isEmpty)
        #expect(clientProxy.pauseServicesModeReceivedInvocations.isEmpty)
    }
    
    private func expectImmediatelyEndedCallReported(forPayload payload: PKPushPayloadMock,
                                                    expectedReason: CXCallEndedReason) async {
        let baselineNewIncomingCount = callProvider.reportNewIncomingCallWithUpdateCompletionCallsCount
        let baselineEndedCount = callProvider.reportCallWithEndedAtReasonCallsCount
        
        await waitForConfirmation { confirmation in
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) {
                confirmation()
            }
        }
        
        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionCallsCount == baselineNewIncomingCount + 1)
        #expect(callProvider.reportCallWithEndedAtReasonCallsCount == baselineEndedCount + 1)
        
        let reportedCall = callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments
        let endedCall = callProvider.reportCallWithEndedAtReasonReceivedArguments
        #expect(reportedCall?.uuid == endedCall?.uuid)
        #expect(endedCall?.reason == expectedReason)
    }
    
    private func makeService(appState: UIApplication.State) {
        let dateProvider: () -> Date = {
            self.currentDate
        }
        service = ElementCallService(callProvider: callProvider,
                                     timeProvider: TimeProvider(clock: testClock, now: dateProvider)) {
            appState
        }
    }
    
    private func expectUnansweredTimeoutScheduled() async {
        await #expect(throws: SuspensionError.self) {
            try await testClock.checkSuspension()
        }
    }
    
    private func expectNoUnansweredTimeoutScheduled() async {
        do {
            try await testClock.checkSuspension()
        } catch {
            Issue.record("Expected no unanswered timeout to be scheduled.")
        }
    }
    
    private func yieldToScheduledObservationTasks() async {
        await testClock.advance()
    }
    
    private actor RoomLookupSequencer {
        enum Lookup {
            case first
            case subsequent
        }
        
        private var lookupCount = 0
        private var firstLookupStartedContinuations = [CheckedContinuation<Void, Never>]()
        private var firstLookupReturnedContinuations = [CheckedContinuation<Void, Never>]()
        private var allowFirstLookupToReturnContinuations = [CheckedContinuation<Void, Never>]()
        private var hasFirstLookupStarted = false
        private var hasFirstLookupReturned = false
        private var canFirstLookupReturn = false
        
        func nextLookup() async -> Lookup {
            lookupCount += 1
            
            guard lookupCount == 1 else {
                return .subsequent
            }
            
            hasFirstLookupStarted = true
            firstLookupStartedContinuations.forEach { $0.resume() }
            firstLookupStartedContinuations.removeAll()
            
            return .first
        }
        
        func waitForFirstLookupStarted() async {
            guard !hasFirstLookupStarted else {
                return
            }
            
            await withCheckedContinuation { continuation in
                firstLookupStartedContinuations.append(continuation)
            }
        }
        
        func waitUntilFirstLookupCanReturn() async {
            guard !canFirstLookupReturn else {
                return
            }
            
            await withCheckedContinuation { continuation in
                allowFirstLookupToReturnContinuations.append(continuation)
            }
        }
        
        func allowFirstLookupToReturn() {
            canFirstLookupReturn = true
            allowFirstLookupToReturnContinuations.forEach { $0.resume() }
            allowFirstLookupToReturnContinuations.removeAll()
        }
        
        func markFirstLookupReturned() {
            hasFirstLookupReturned = true
            firstLookupReturnedContinuations.forEach { $0.resume() }
            firstLookupReturnedContinuations.removeAll()
        }
        
        func waitForFirstLookupReturned() async {
            guard !hasFirstLookupReturned else {
                return
            }
            
            await withCheckedContinuation { continuation in
                firstLookupReturnedContinuations.append(continuation)
            }
        }
    }
}

private nonisolated class PKPushPayloadMock: PKPushPayload {
    var dict: [AnyHashable: Any] = [:]
    
    override init() {
        dict[ElementCallServiceNotificationKey.roomID.rawValue] = "!room:example.com"
        dict[ElementCallServiceNotificationKey.roomDisplayName.rawValue] = "welcome"
        dict[ElementCallServiceNotificationKey.rtcNotifyEventID.rawValue] = "$000"
        dict[ElementCallServiceNotificationKey.expirationDate.rawValue] = Date(timeIntervalSince1970: 10)
    }
    
    override var dictionaryPayload: [AnyHashable: Any] {
        dict
    }
    
    func updatingExpiration(_ from: Date, lifetime: TimeInterval) -> Self {
        dict[ElementCallServiceNotificationKey.expirationDate.rawValue] = from.addingTimeInterval(lifetime)
        return self
    }
    
    func updateIsVoice(_ isVoice: Bool) -> Self {
        dict[ElementCallServiceNotificationKey.isVoiceCall.rawValue] = isVoice
        return self
    }
    
    func updatingRTCNotificationID(_ rtcNotificationID: String) -> Self {
        dict[ElementCallServiceNotificationKey.rtcNotifyEventID.rawValue] = rtcNotificationID
        return self
    }
}
