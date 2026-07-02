//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
@testable import ElementX
import MatrixRustSDK
import MatrixRustSDKMocks
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
        #expect(harness.operations.prefix(2) == [.presence(.unavailable, true), .syncStop])
    }
    
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

private final class ClientProxyPresenceHarness {
    enum RecordedPresence: Equatable, Sendable {
        case online
        case unavailable
        case offline
        
        init(_ presence: PresenceState) {
            switch presence {
            case .online:
                self = .online
            case .unavailable:
                self = .unavailable
            case .offline:
                self = .offline
            }
        }
    }
    
    enum Operation: Equatable, Sendable {
        case presence(RecordedPresence, Bool)
        case syncStart
        case syncStop
        case clientResume
        case clientPause
    }
    
    fileprivate struct SequencedOperation: Sendable {
        let sequence: Int
        let operation: Operation
    }
    
    let appSettings: AppSettings
    let client: ClientSDKMock
    let syncService: SyncServiceSDKMock
    let proxy: ClientProxy
    let networkReachabilitySubject: CurrentValueSubject<NetworkMonitorReachability, Never>
    
    var operations = [Operation]()
    
    private let operationStream: AsyncStream<SequencedOperation>
    private let operationContinuation: AsyncStream<SequencedOperation>.Continuation
    private var nextOperationSequence = 0
    
    init(sharePresence: Bool = true, networkReachability: NetworkMonitorReachability = .reachable) async throws {
        let operationStream = AsyncStream<SequencedOperation>.makeStream()
        self.operationStream = operationStream.stream
        operationContinuation = operationStream.continuation
        
        appSettings = .volatile()
        appSettings.sharePresence = sharePresence
        
        client = ClientSDKMock(.init(userID: "@alice:matrix.org"))
        syncService = SyncServiceSDKMock()
        networkReachabilitySubject = .init(networkReachability)
        
        Self.configure(client: client, syncService: syncService)
        
        proxy = try await ClientProxy(client: client,
                                      networkMonitor: NetworkMonitorMock(.init(reachabilityPublisher: networkReachabilitySubject.asCurrentValuePublisher())),
                                      appSettings: appSettings,
                                      analyticsService: AnalyticsServiceMock(.init()),
                                      restartServicesDelay: .zero)
        configureOperationRecording()
    }
    
    deinit {
        operationContinuation.finish()
    }
    
    fileprivate func fulfillment(for operation: Operation) -> DeferredFulfillment<SequencedOperation> {
        let minimumSequence = nextOperationSequence
        return deferFulfillment(operationStream, message: "Expected operation: \(operation)") {
            $0.sequence >= minimumSequence && $0.operation == operation
        }
    }
    
    func blockSyncStart(until stream: AsyncStream<Void>) {
        syncService.startClosure = { [weak self] in
            self?.record(.syncStart)
            for await _ in stream {
                break
            }
        }
    }
    
    func blockSyncStop(until stream: AsyncStream<Void>) {
        syncService.stopClosure = { [weak self] in
            self?.record(.syncStop)
            for await _ in stream {
                break
            }
        }
    }
    
    private func configureOperationRecording() {
        client.setPresencePresenceImmediateClosure = { [weak self] presence, immediate in
            self?.record(.presence(.init(presence), immediate))
        }
        client.resumeClosure = { [weak self] in
            self?.record(.clientResume)
        }
        client.pauseClosure = { [weak self] in
            self?.record(.clientPause)
        }
        syncService.startClosure = { [weak self] in
            self?.record(.syncStart)
        }
        syncService.stopClosure = { [weak self] in
            self?.record(.syncStop)
        }
    }
    
    private func record(_ operation: Operation) {
        let sequencedOperation = SequencedOperation(sequence: nextOperationSequence, operation: operation)
        nextOperationSequence += 1
        operations.append(operation)
        operationContinuation.yield(sequencedOperation)
    }
    
    private static func configure(client: ClientSDKMock, syncService: SyncServiceSDKMock) {
        let taskHandle = TaskHandleSDKMock()
        taskHandle.isFinishedReturnValue = false
        
        let notificationSettings = NotificationSettingsSDKMock()
        client.getNotificationSettingsReturnValue = notificationSettings
        
        let encryption = EncryptionSDKMock()
        encryption.backupStateListenerListenerReturnValue = taskHandle
        encryption.recoveryStateListenerListenerReturnValue = taskHandle
        encryption.backupExistsOnServerReturnValue = true
        encryption.verificationStateReturnValue = .verified
        encryption.verificationStateListenerListenerReturnValue = taskHandle
        client.encryptionReturnValue = encryption
        
        client.getSessionVerificationControllerReturnValue = SessionVerificationControllerSDKMock()
        
        let spaceService = SpaceServiceSDKMock()
        spaceService.subscribeToTopLevelJoinedSpacesListenerReturnValue = taskHandle
        spaceService.subscribeToSpaceFiltersListenerReturnValue = taskHandle
        client.spaceServiceReturnValue = spaceService
        
        let capabilities = HomeserverCapabilitiesSDKMock()
        capabilities.canChangeAvatarReturnValue = true
        capabilities.canChangeDisplaynameReturnValue = true
        client.homeserverCapabilitiesReturnValue = capabilities
        
        let dynamicEntriesController = RoomListDynamicEntriesControllerSDKMock()
        dynamicEntriesController.setFilterKindReturnValue = true
        
        let dynamicAdaptersResult = RoomListEntriesWithDynamicAdaptersResultSDKMock()
        dynamicAdaptersResult.controllerReturnValue = dynamicEntriesController
        
        let roomList = RoomListSDKMock()
        roomList.entriesWithDynamicAdaptersPageSizeListenerReturnValue = dynamicAdaptersResult
        roomList.loadingStateListenerReturnValue = .some(.init(state: .notLoaded, stateStream: taskHandle))
        
        let roomListService = RoomListServiceSDKMock()
        roomListService.allRoomsReturnValue = roomList
        roomListService.stateListenerReturnValue = taskHandle
        roomListService.syncIndicatorDelayBeforeShowingInMsDelayBeforeHidingInMsListenerReturnValue = taskHandle
        
        syncService.roomListServiceReturnValue = roomListService
        syncService.stateListenerReturnValue = taskHandle
        
        let syncServiceBuilder = SyncServiceBuilderSDKMock()
        syncServiceBuilder.withOfflineModeReturnValue = syncServiceBuilder
        syncServiceBuilder.withSharePosEnableReturnValue = syncServiceBuilder
        syncServiceBuilder.finishReturnValue = syncService
        client.syncServiceReturnValue = syncServiceBuilder
        
        client.setDelegateDelegateReturnValue = taskHandle
        client.subscribeToIgnoredUsersListenerReturnValue = taskHandle
        client.subscribeToSendQueueStatusListenerReturnValue = taskHandle
        client.subscribeToSendQueueUpdatesListenerReturnValue = taskHandle
        client.subscribeToMediaPreviewConfigListenerReturnValue = taskHandle
        client.subscribeToOwnBeaconInfoUpdatesListenerReturnValue = taskHandle
        client.cachedAvatarUrlReturnValue = nil
        client.accountUrlActionReturnValue = nil
    }
}
