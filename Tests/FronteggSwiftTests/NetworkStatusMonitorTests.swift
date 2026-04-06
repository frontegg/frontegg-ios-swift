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

    func test_handlerRemovalByIndex_preservesStableIndicesForRemainingHandlers() {
        let emitted = expectation(description: "Remaining handlers should be called")
        emitted.expectedFulfillmentCount = 2
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

        wait(for: [emitted], timeout: 1.0)
        XCTAssertFalse(received.contains("first:true"))
        XCTAssertTrue(received.contains("second:true"))
        XCTAssertTrue(received.contains("third:true"))
    }

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

    func test_forceEmit_notifiesHandlersWithoutStateChange() {
        let emitted = expectation(description: "Force emit should notify even without change")
        emitted.expectedFulfillmentCount = 2
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
