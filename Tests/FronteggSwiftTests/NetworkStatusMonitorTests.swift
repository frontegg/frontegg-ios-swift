//
//  NetworkStatusMonitorTests.swift
//  FronteggSwiftTests
//

import XCTest
import CFNetwork
@testable import FronteggSwift

final class NetworkStatusMonitorTests: XCTestCase {

    override func setUp() {
        super.setUp()
        NetworkStatusMonitor._testReset()
    }

    override func tearDown() {
        NetworkStatusMonitor._testReset()
        super.tearDown()
    }

    func test_isConnectivityError_detectsTransientRefreshApiError() {
        XCTAssertTrue(
            isConnectivityError(
                ApiError.refreshEndpointTransient(statusCode: 502, message: "temporary")
            )
        )
    }

    func test_isConnectivityError_detectsNestedURLError() {
        let nested = NSError(domain: NSURLErrorDomain, code: URLError.notConnectedToInternet.rawValue)
        let wrapped = NSError(domain: "outer", code: 1, userInfo: [NSUnderlyingErrorKey: nested])

        XCTAssertTrue(isConnectivityError(wrapped))
    }

    func test_isConnectivityError_detectsCFNetworkAndPosixTransportErrors() {
        let cfNetwork = NSError(domain: kCFErrorDomainCFNetwork as String, code: -72000)
        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(POSIXError.Code.ENETUNREACH.rawValue))

        XCTAssertTrue(isConnectivityError(cfNetwork))
        XCTAssertTrue(isConnectivityError(posix))
    }

    func test_isConnectivityError_detectsTimeoutAndRedirectResponses() {
        let url = URL(string: "https://test.example.com")!
        let timeoutResponse = HTTPURLResponse(url: url, statusCode: 408, httpVersion: nil, headerFields: nil)!
        let redirectResponse = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil)!

        XCTAssertTrue(isConnectivityError(NSError(domain: "test", code: 1), response: timeoutResponse))
        XCTAssertTrue(isConnectivityError(NSError(domain: "test", code: 1), response: redirectResponse))
    }

    func test_isConnectivityError_cancelledRequestIsNotConnectivityFailure() {
        XCTAssertFalse(isConnectivityError(URLError(.cancelled)))
    }

    @MainActor
    func test_handlerRemovalByIndex_preservesStableIndicesForRemainingHandlers() {
        let emitted = expectation(description: "Remaining handlers should be called")
        emitted.expectedFulfillmentCount = 2
        emitted.assertForOverFulfill = false
        var received: [String] = []

        let firstIndex = NetworkStatusMonitor.addOnChange { value in
            received.append("first:\(value)")
        }
        let secondIndex = NetworkStatusMonitor.addOnChange { value in
            received.append("second:\(value)")
            emitted.fulfill()
        }

        NetworkStatusMonitor.removeOnChange(at: firstIndex)

        let thirdIndex = NetworkStatusMonitor.addOnChange { value in
            received.append("third:\(value)")
            emitted.fulfill()
        }

        XCTAssertEqual(firstIndex, 0)
        XCTAssertEqual(secondIndex, 1)
        XCTAssertEqual(thirdIndex, 2)

        NetworkStatusMonitor._testEmitCached(true, forceEmit: true)

        wait(for: [emitted], timeout: 3.0)
        XCTAssertFalse(received.contains("first:true"))
        XCTAssertTrue(received.contains("second:true"))
        XCTAssertTrue(received.contains("third:true"))
    }

    @MainActor
    func test_removeOnChangeByToken_preventsFurtherNotifications() {
        let notCalled = expectation(description: "Removed token should not receive updates")
        notCalled.isInverted = true

        let token = NetworkStatusMonitor.addOnChangeReturningToken { _ in
            notCalled.fulfill()
        }

        NetworkStatusMonitor.removeOnChange(token)
        NetworkStatusMonitor._testEmitCached(true, forceEmit: true)

        wait(for: [notCalled], timeout: 0.2)
    }

    @MainActor
    func test_forceEmit_notifiesHandlersWithoutStateChange() {
        let emitted = expectation(description: "Force emit should notify even without change")
        emitted.expectedFulfillmentCount = 2
        emitted.assertForOverFulfill = false
        var received: [Bool] = []

        _ = NetworkStatusMonitor.addOnChange { value in
            received.append(value)
            emitted.fulfill()
        }

        NetworkStatusMonitor._testEmitCached(false, forceEmit: true)
        NetworkStatusMonitor._testEmitCached(false, forceEmit: true)

        wait(for: [emitted], timeout: 1.0)
        XCTAssertEqual(received, [false, false])
    }

    func test_isActive_returnsCachedValueWhenMonitoringIsActive() async {
        NetworkStatusMonitor._testSetState(
            cachedReachable: true,
            hasCachedReachable: true,
            monitoringActive: true,
            hasInitialCheckFired: true
        )

        let active = await NetworkStatusMonitor.isActive

        XCTAssertTrue(active)
    }

    func test_stopBackgroundMonitoring_resetsCachedState() {
        NetworkStatusMonitor._testSetState(
            cachedReachable: true,
            hasCachedReachable: true,
            monitoringActive: true,
            hasInitialCheckFired: true
        )

        NetworkStatusMonitor.stopBackgroundMonitoring()
        let snapshot = NetworkStatusMonitor._testSnapshot()

        XCTAssertFalse(snapshot.cachedReachable)
        XCTAssertFalse(snapshot.hasCachedReachable)
        XCTAssertFalse(snapshot.monitoringActive)
        XCTAssertFalse(snapshot.hasInitialCheckFired)
    }

    // MARK: - One-shot CheckedContinuation safety (issue #256)
    //
    // `NWPathMonitor.pathUpdateHandler` is invoked once at start and again on every
    // subsequent path change (Wi-Fi ↔ cellular handoff, VPN reconnect, sleep/wake).
    // The previous `routeIsAvailableOnce()` implementation called
    // `continuation.resume` directly inside that handler, so a second fire produced
    // an `EXC_BREAKPOINT` from Swift's `_checkedContinuationViolated` precondition.
    // These tests pin the new single-resume invariant: even under rapid, sequential,
    // or massively concurrent re-entries of the callback, the continuation must be
    // resumed at most once and the host process must not crash.
    //
    // The Swift runtime aborts the test process when a CheckedContinuation is resumed
    // twice, so if any of these regress, the test target will SIGTRAP rather than fail
    // a single assertion. That's intentional — it's the same signal customers saw.

    func test_awaitFirstBoolResult_singleFire_returnsValue() async {
        let result = await NetworkStatusMonitor._testAwaitFirstBoolResult { resume in
            resume(true)
        }
        XCTAssertTrue(result)
    }

    func test_awaitFirstBoolResult_sequentialDoubleFire_doesNotCrash_andReturnsFirstValue() async {
        // Simulates `NWPathMonitor` firing twice back-to-back on the same serial queue,
        // which is exactly the case that produced the EXC_BREAKPOINT in production.
        let result = await NetworkStatusMonitor._testAwaitFirstBoolResult { resume in
            resume(true)
            resume(false)
            resume(true)
        }
        XCTAssertTrue(result, "First resume must win; subsequent resumes must be no-ops")
    }

    func test_awaitFirstBoolResult_asyncDoubleFire_doesNotCrash() async {
        // Simulates the realistic ordering: handler is delivered on a background serial
        // queue and fires again later as the path settles (VPN reconnect, captive portal).
        let queue = DispatchQueue(label: "test.awaitFirstBoolResult.async")
        let result = await NetworkStatusMonitor._testAwaitFirstBoolResult { resume in
            queue.async {
                resume(true)
                // Even after a brief delay simulating a follow-up path change,
                // resuming again must not trip the runtime precondition.
                queue.asyncAfter(deadline: .now() + 0.01) {
                    resume(false)
                }
            }
        }
        XCTAssertTrue(result)
    }

    func test_awaitFirstBoolResult_concurrentFiresFromManyThreads_doesNotCrash() async {
        // Hammers the gate from multiple threads simultaneously. If the lock-guarded
        // `didResume` flag ever lets two callers through, the runtime will SIGTRAP.
        //
        // We block synchronously inside the continuation body on `group.wait()` so
        // every one of the 128 dispatched calls has actually been delivered to the
        // gate before `body` returns. Without this wait, `body` could return (and the
        // first `resume` could wake the await) before later closures even fire — the
        // test would pass without genuinely exercising the concurrent re-entry path.
        let result = await NetworkStatusMonitor._testAwaitFirstBoolResult { resume in
            let group = DispatchGroup()
            for index in 0..<128 {
                group.enter()
                DispatchQueue.global().async {
                    // Mix true/false to also assert that "first wins" is the contract,
                    // not "last wins" or some race-y blend.
                    resume(index % 2 == 0)
                    group.leave()
                }
            }
            group.wait()
        }
        // Any caller could have been first — only the no-crash invariant matters here.
        _ = result
    }

    func test_routeIsAvailableOnce_returnsBoolWithoutCrash() async {
        // End-to-end smoke test against the real `NWPathMonitor`-backed implementation.
        // The actual value depends on the test host's network, so we just assert
        // the call completes — the regression we care about is the crash, not a value.
        _ = await NetworkStatusMonitor._testRouteIsAvailableOnce()
    }

    func test_routeIsAvailableOnce_completesWithinDeadline() async {
        // Defensive bound: even if `NWPathMonitor` never delivers an update (a real
        // edge case seen with stalled VPN/MDM profiles and on isolated CI runners),
        // the call must not hang the caller. The internal timeout is 1s; we allow
        // a generous 3s envelope to absorb scheduler jitter on slow CI.
        let start = Date()
        _ = await NetworkStatusMonitor._testRouteIsAvailableOnce()
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(
            elapsed,
            3.0,
            "routeIsAvailableOnce must not hang when the path monitor is slow or stalled"
        )
    }

    func test_awaitFirstBoolResult_lateSecondFireAfterResumeIsHarmless() async {
        // Models the exact production timing: the first path-update resumes, then a
        // second update arrives moments later from the same serial queue. The gate
        // must drop the late call silently so the timeout path in `routeIsAvailableOnce`
        // (which also calls `resume(false)` after `timeout` seconds) can never re-enter
        // a continuation that the path update already resumed.
        let queue = DispatchQueue(label: "test.lateSecondFire")
        let lateFired = expectation(description: "late resume fired without crashing")
        let result = await NetworkStatusMonitor._testAwaitFirstBoolResult { resume in
            // First fire immediately on the serial queue — this wins the gate.
            queue.async {
                resume(true)
            }
            // Second fire arrives later on the same queue, after the await has
            // already resumed. If the gate ever lets it through, the runtime
            // will SIGTRAP on the double-resume of the continuation.
            queue.asyncAfter(deadline: .now() + 0.05) {
                resume(false)
                lateFired.fulfill()
            }
        }
        await fulfillment(of: [lateFired], timeout: 1.0)
        XCTAssertTrue(result, "first resume(true) must win; late resume(false) must be dropped")
    }

    func test_routeIsAvailableOnce_repeatedRapidCalls_doNotCrash() async {
        // Issues many overlapping invocations to maximise the chance of catching a
        // double-resume regression. Each call instantiates its own NWPathMonitor and
        // its own continuation, but they share `pathQueue`, so any serialization
        // assumptions get exercised here too.
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    _ = await NetworkStatusMonitor._testRouteIsAvailableOnce()
                }
            }
        }
    }

    func test_probeConfiguredReachability_withoutConfiguredBaseURL_doesNotCrash() async {
        // `probeConfiguredReachability()` falls through to `routeIsAvailableOnce()`
        // when no base URL is configured. This is the exact call path used by
        // `FronteggAuth.completeUnauthenticatedStartupInitialization` during the
        // app-launch connectivity race, which is where customers saw the crash.
        // The `_testReset()` in `setUp` ensures no base URL is configured.
        _ = await NetworkStatusMonitor.probeConfiguredReachability()
    }

    func test_isActive_whenNotMonitoring_doesNotCrash() async {
        // The 1.2.21 crash signature pointed at `NetworkStatusMonitor.isActive`,
        // which on master delegates to `probeReachability` → `routeIsAvailableOnce`
        // when background monitoring is inactive. Cover the same call shape.
        let snapshot = NetworkStatusMonitor._testSnapshot()
        XCTAssertFalse(snapshot.monitoringActive, "Sanity: setUp should leave monitoring inactive")
        _ = await NetworkStatusMonitor.isActive
    }

    @MainActor
    func test_staleMonitoringGeneration_doesNotNotifyHandlersAfterStop() {
        let notCalled = expectation(description: "Stale monitoring generation should not notify")
        notCalled.isInverted = true

        NetworkStatusMonitor.startBackgroundMonitoring(emitInitialState: false)
        let staleGeneration = NetworkStatusMonitor._testCurrentMonitoringGeneration()
        NetworkStatusMonitor.stopBackgroundMonitoring()

        _ = NetworkStatusMonitor.addOnChange { _ in
            notCalled.fulfill()
        }

        NetworkStatusMonitor._testEmitCachedForMonitoringGeneration(
            true,
            expectedGeneration: staleGeneration,
            forceEmit: true
        )

        wait(for: [notCalled], timeout: 0.2)
    }
}
