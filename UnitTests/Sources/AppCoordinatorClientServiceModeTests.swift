//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Testing
import UIKit

@MainActor
struct AppCoordinatorClientServiceModeTests {
    @Test
    func backgroundRefreshPassesBackgroundSync() async {
        let clientProxy = ClientProxyMock(.init())
        
        await clientProxy.resumeServices(mode: AppCoordinatorClientServiceModeResolver.backgroundRefreshResumeMode())
        
        #expect(clientProxy.resumeServicesModeReceivedInvocations == [.backgroundSync])
    }
    
    @Test
    func manualBackgroundWorkUsesForegroundOnlyWhenActive() async {
        for (appState, expectedMode) in activeOrBackgroundSyncCases {
            let clientProxy = ClientProxyMock(.init())
            let mode = AppCoordinatorClientServiceModeResolver.resumeMode(for: .manualBackgroundWork, appState: appState)
            
            await clientProxy.resumeServices(mode: mode)
            
            #expect(clientProxy.resumeServicesModeReceivedInvocations == [expectedMode])
        }
    }
    
    @Test
    func inlineReplyUsesForegroundOnlyWhenActive() async {
        for (appState, expectedMode) in activeOrBackgroundSyncCases {
            let clientProxy = ClientProxyMock(.init())
            let mode = AppCoordinatorClientServiceModeResolver.resumeMode(for: .inlineReply, appState: appState)
            
            await clientProxy.resumeServices(mode: mode)
            
            #expect(clientProxy.resumeServicesModeReceivedInvocations == [expectedMode])
            #expect(!clientProxy.resumeServicesModeReceivedInvocations.contains(.backgroundGrace))
        }
    }
    
    @Test
    func restoredSessionUsesPendingInlineReplySignal() async {
        let cases = [
            RestoredSessionModeCase(appState: .active, hasPendingStoredInlineReply: true, expectedMode: .foregroundActive),
            RestoredSessionModeCase(appState: .active, hasPendingStoredInlineReply: false, expectedMode: .foregroundActive),
            RestoredSessionModeCase(appState: .inactive, hasPendingStoredInlineReply: true, expectedMode: .backgroundSync),
            RestoredSessionModeCase(appState: .background, hasPendingStoredInlineReply: true, expectedMode: .backgroundSync),
            RestoredSessionModeCase(appState: .inactive, hasPendingStoredInlineReply: false, expectedMode: .backgroundGrace),
            RestoredSessionModeCase(appState: .background, hasPendingStoredInlineReply: false, expectedMode: .backgroundGrace)
        ]
        
        for modeCase in cases {
            let clientProxy = ClientProxyMock(.init())
            let mode = AppCoordinatorClientServiceModeResolver.resumeMode(for: .restoredSession(hasPendingStoredInlineReply: modeCase.hasPendingStoredInlineReply),
                                                                          appState: modeCase.appState)
            
            await clientProxy.resumeServices(mode: mode)
            
            #expect(clientProxy.resumeServicesModeReceivedInvocations == [modeCase.expectedMode])
        }
    }
    
    @Test
    func backgroundEntryUsesModeUpdateNotResume() async {
        let clientProxy = ClientProxyMock(.init())
        
        await clientProxy.updateServiceMode(AppCoordinatorClientServiceModeResolver.backgroundEnteredModeUpdate())
        
        #expect(clientProxy.updateServiceModeReceivedInvocations == [.backgroundGrace])
        #expect(clientProxy.resumeServicesModeReceivedInvocations.isEmpty)
    }
    
    @Test
    func inactiveEntryUsesModeUpdateNotResume() async {
        let clientProxy = ClientProxyMock(.init())
        
        await clientProxy.updateServiceMode(AppCoordinatorClientServiceModeResolver.inactiveModeUpdate())
        
        #expect(clientProxy.updateServiceModeReceivedInvocations == [.backgroundGrace])
        #expect(clientProxy.resumeServicesModeReceivedInvocations.isEmpty)
    }
    
    @Test
    func foregroundEntryDoesNotRequestForegroundActiveUntilDidBecomeActive() async {
        let clientProxy = ClientProxyMock(.init())
        
        #expect(AppCoordinatorClientServiceModeResolver.foregroundEnteredAction() == nil)
        await clientProxy.resumeServices(mode: AppCoordinatorClientServiceModeResolver.activeForegroundResumeMode())
        
        #expect(clientProxy.resumeServicesModeReceivedInvocations == [.foregroundActive])
    }
    
    @Test
    func backgroundPauseUsesBackgroundGrace() async {
        let clientProxy = ClientProxyMock(.init())
        
        await clientProxy.pauseServices(mode: AppCoordinatorClientServiceModeResolver.backgroundPauseMode())
        
        #expect(clientProxy.pauseServicesModeReceivedInvocations == [.backgroundGrace])
    }
    
    private var activeOrBackgroundSyncCases: [(UIApplication.State, ClientServiceRunMode)] {
        [
            (.active, .foregroundActive),
            (.inactive, .backgroundSync),
            (.background, .backgroundSync)
        ]
    }
}

private struct RestoredSessionModeCase {
    let appState: UIApplication.State
    let hasPendingStoredInlineReply: Bool
    let expectedMode: ClientServiceRunMode
}
