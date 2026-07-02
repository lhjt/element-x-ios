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

final class ClientProxyPresenceHarness {
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
    
    struct SequencedOperation: Sendable {
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
    
    init(sharePresence: Bool = true,
         networkReachability: NetworkMonitorReachability = .reachable,
         restartServicesDelay: Duration = .zero) async throws {
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
                                      restartServicesDelay: restartServicesDelay)
        configureOperationRecording()
    }
    
    deinit {
        operationContinuation.finish()
    }
    
    func fulfillment(for operation: Operation) -> DeferredFulfillment<SequencedOperation> {
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
    
    func blockPresence(until stream: AsyncStream<Void>) {
        client.setPresencePresenceImmediateClosure = { [weak self] presence, immediate in
            self?.record(.presence(.init(presence), immediate))
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
