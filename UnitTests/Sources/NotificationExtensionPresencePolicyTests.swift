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
        
        #expect(!NotificationExtensionPresencePolicy(mainAppActivityState: .foregroundActive,
                                                     mainAppActivityStateLastUpdatedSystemUptime: currentSystemUptime)
                .shouldForceOfflinePresence(currentSystemUptime: currentSystemUptime))
        #expect(!NotificationExtensionPresencePolicy(mainAppActivityState: .foregroundActive,
                                                     mainAppActivityStateLastUpdatedSystemUptime: currentSystemUptime - NotificationExtensionPresencePolicy.foregroundActiveMaximumAge)
                .shouldForceOfflinePresence(currentSystemUptime: currentSystemUptime))
    }
    
    @Test
    func staleForegroundActiveStateForcesOfflinePresence() {
        let currentSystemUptime: TimeInterval = 100
        let staleSystemUptime = currentSystemUptime - NotificationExtensionPresencePolicy.foregroundActiveMaximumAge - 1
        
        #expect(NotificationExtensionPresencePolicy(mainAppActivityState: .foregroundActive,
                                                    mainAppActivityStateLastUpdatedSystemUptime: staleSystemUptime)
                .shouldForceOfflinePresence(currentSystemUptime: currentSystemUptime))
    }
    
    @Test
    func missingOrFutureForegroundActiveTimestampForcesOfflinePresence() {
        let currentSystemUptime: TimeInterval = 100
        
        #expect(NotificationExtensionPresencePolicy(mainAppActivityState: .foregroundActive,
                                                    mainAppActivityStateLastUpdatedSystemUptime: nil)
                .shouldForceOfflinePresence(currentSystemUptime: currentSystemUptime))
        #expect(NotificationExtensionPresencePolicy(mainAppActivityState: .foregroundActive,
                                                    mainAppActivityStateLastUpdatedSystemUptime: currentSystemUptime + 1)
                .shouldForceOfflinePresence(currentSystemUptime: currentSystemUptime))
    }
    
    @Test
    func nonForegroundActiveStateForcesOfflinePresence() {
        let currentSystemUptime: TimeInterval = 100
        
        for mainAppActivityState in [MainAppActivityState.inactive, .background, .terminated] {
            #expect(NotificationExtensionPresencePolicy(mainAppActivityState: mainAppActivityState,
                                                        mainAppActivityStateLastUpdatedSystemUptime: currentSystemUptime)
                    .shouldForceOfflinePresence(currentSystemUptime: currentSystemUptime))
        }
    }
}
