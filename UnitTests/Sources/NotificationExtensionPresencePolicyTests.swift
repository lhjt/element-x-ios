//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import Testing

struct NotificationExtensionPresencePolicyTests {
    @Test
    func freshForegroundActiveStateSkipsForcingOfflinePresence() {
        let currentSystemUptime: TimeInterval = 100
        
        #expect(!NotificationExtensionPresencePolicy(sharePresence: true,
                                                     mainAppActivityStateSnapshot: snapshot(lastUpdatedSystemUptime: currentSystemUptime))
                .shouldForceOfflinePresence(currentSystemUptime: currentSystemUptime))
        #expect(!NotificationExtensionPresencePolicy(sharePresence: true,
                                                     mainAppActivityStateSnapshot: snapshot(lastUpdatedSystemUptime: currentSystemUptime - NotificationExtensionPresencePolicy.foregroundActiveMaximumAge))
                .shouldForceOfflinePresence(currentSystemUptime: currentSystemUptime))
    }
    
    @Test
    func staleForegroundActiveStateForcesOfflinePresence() {
        let currentSystemUptime: TimeInterval = 100
        let staleSystemUptime = currentSystemUptime - NotificationExtensionPresencePolicy.foregroundActiveMaximumAge - 1
        
        #expect(NotificationExtensionPresencePolicy(sharePresence: true,
                                                    mainAppActivityStateSnapshot: snapshot(lastUpdatedSystemUptime: staleSystemUptime))
                .shouldForceOfflinePresence(currentSystemUptime: currentSystemUptime))
    }
    
    @Test
    func missingOrFutureForegroundActiveTimestampForcesOfflinePresence() {
        let currentSystemUptime: TimeInterval = 100
        
        #expect(NotificationExtensionPresencePolicy(sharePresence: true,
                                                    mainAppActivityStateSnapshot: snapshot(lastUpdatedSystemUptime: nil))
                .shouldForceOfflinePresence(currentSystemUptime: currentSystemUptime))
        #expect(NotificationExtensionPresencePolicy(sharePresence: true,
                                                    mainAppActivityStateSnapshot: snapshot(lastUpdatedSystemUptime: currentSystemUptime + 1))
                .shouldForceOfflinePresence(currentSystemUptime: currentSystemUptime))
    }
    
    @Test
    func nonForegroundActiveStateForcesOfflinePresence() {
        let currentSystemUptime: TimeInterval = 100
        
        for mainAppActivityState in [MainAppActivityState.inactive, .background, .terminated] {
            #expect(NotificationExtensionPresencePolicy(sharePresence: true,
                                                        mainAppActivityStateSnapshot: snapshot(state: mainAppActivityState,
                                                                                               lastUpdatedSystemUptime: currentSystemUptime))
                    .shouldForceOfflinePresence(currentSystemUptime: currentSystemUptime))
        }
    }
    
    @Test
    func disabledSharePresenceForcesOfflinePresence() {
        let currentSystemUptime: TimeInterval = 100
        
        #expect(NotificationExtensionPresencePolicy(sharePresence: false,
                                                    mainAppActivityStateSnapshot: snapshot(lastUpdatedSystemUptime: currentSystemUptime))
                .shouldForceOfflinePresence(currentSystemUptime: currentSystemUptime))
    }
    
    @Test
    func appSettingsStoresMainAppActivityStateSnapshot() {
        let store = VolatileUserDefaults()
        let appSettings = AppSettings(store: store)
        
        appSettings.updateMainAppActivityState(.foregroundActive, systemUptime: 100)
        
        #expect(appSettings.mainAppActivityStateSnapshot == .init(state: .foregroundActive, lastUpdatedSystemUptime: 100))
        #expect(store.data(forKey: "mainAppActivityStateSnapshot") != nil)
        #expect(store.object(forKey: "mainAppActivityState") == nil)
        #expect(store.object(forKey: "mainAppActivityStateLastUpdatedSystemUptime") == nil)
    }
    
    private func snapshot(state: MainAppActivityState = .foregroundActive,
                          lastUpdatedSystemUptime: TimeInterval?) -> MainAppActivityStateSnapshot {
        MainAppActivityStateSnapshot(state: state, lastUpdatedSystemUptime: lastUpdatedSystemUptime)
    }
}
