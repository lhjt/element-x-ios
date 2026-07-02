//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Testing

nonisolated enum BackgroundSyncLeaseEvent: Equatable, Sendable {
    case acquire(Int)
    case send
    case stop
    case release(Int)
    case pause
}

actor BackgroundSyncLeaseRecorder {
    private let recordsPauseWhenIdle: Bool
    private var nextLeaseID = 0
    private var activeLeaseIDs = Set<Int>()
    private var events = [BackgroundSyncLeaseEvent]()
    private var continuations = [AsyncStream<BackgroundSyncLeaseEvent>.Continuation]()
    private var eventWaiters = [EventWaiter]()
    
    init(recordsPauseWhenIdle: Bool = false) {
        self.recordsPauseWhenIdle = recordsPauseWhenIdle
    }
    
    var recordedEvents: [BackgroundSyncLeaseEvent] {
        events
    }
    
    func eventStream() -> AsyncStream<BackgroundSyncLeaseEvent> {
        let (stream, continuation) = AsyncStream<BackgroundSyncLeaseEvent>.makeStream()
        continuations.append(continuation)
        events.forEach { continuation.yield($0) }
        return stream
    }
    
    func acquire() -> ClientProxyBackgroundSyncLeaseProtocol {
        nextLeaseID += 1
        let leaseID = nextLeaseID
        activeLeaseIDs.insert(leaseID)
        record(.acquire(leaseID))
        return BackgroundSyncLease(leaseID: leaseID, recorder: self)
    }
    
    func record(_ event: BackgroundSyncLeaseEvent) {
        events.append(event)
        continuations.forEach { $0.yield(event) }
        resumeSatisfiedEventWaiters()
    }
    
    fileprivate func release(leaseID: Int) {
        guard activeLeaseIDs.remove(leaseID) != nil else {
            return
        }
        
        record(.release(leaseID))
        
        if recordsPauseWhenIdle, activeLeaseIDs.isEmpty {
            record(.pause)
        }
    }
    
    func waitForEvents(_ expectedEvents: [BackgroundSyncLeaseEvent], sourceLocation: SourceLocation = #_sourceLocation) async {
        switch resolution(for: expectedEvents, sourceLocation: sourceLocation) {
        case .satisfied, .impossible:
            return
        case .waiting:
            break
        }
        
        await withCheckedContinuation { continuation in
            eventWaiters.append(.init(expectedEvents: expectedEvents, continuation: continuation, sourceLocation: sourceLocation))
            resumeSatisfiedEventWaiters()
        }
    }
    
    private func resumeSatisfiedEventWaiters() {
        var remainingWaiters = [EventWaiter]()
        
        for waiter in eventWaiters {
            switch resolution(for: waiter.expectedEvents, sourceLocation: waiter.sourceLocation) {
            case .satisfied, .impossible:
                waiter.continuation.resume()
            case .waiting:
                remainingWaiters.append(waiter)
            }
        }
        
        eventWaiters = remainingWaiters
    }
    
    private func resolution(for expectedEvents: [BackgroundSyncLeaseEvent], sourceLocation: SourceLocation) -> EventWaiterResolution {
        if events == expectedEvents {
            return .satisfied
        }
        
        guard expectedEvents.starts(with: events) else {
            Issue.record("Background sync lease events did not match. Expected: \(expectedEvents), recorded: \(events)", sourceLocation: sourceLocation)
            return .impossible
        }
        
        return .waiting
    }
    
    private struct EventWaiter {
        let expectedEvents: [BackgroundSyncLeaseEvent]
        let continuation: CheckedContinuation<Void, Never>
        let sourceLocation: SourceLocation
    }
    
    private enum EventWaiterResolution {
        case satisfied
        case impossible
        case waiting
    }
}

private actor BackgroundSyncLease: ClientProxyBackgroundSyncLeaseProtocol {
    private let leaseID: Int
    private let recorder: BackgroundSyncLeaseRecorder
    private var hasReleased = false
    
    init(leaseID: Int, recorder: BackgroundSyncLeaseRecorder) {
        self.leaseID = leaseID
        self.recorder = recorder
    }
    
    func release() async {
        guard !hasReleased else {
            return
        }
        
        hasReleased = true
        await recorder.release(leaseID: leaseID)
    }
}
