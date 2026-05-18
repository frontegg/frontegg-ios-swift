//
//  FronteggAuthFeatureFlagsRaceTests.swift
//  FronteggSwiftTests
//
//  Regression test for the FronteggAuth.featureFlags data race that hung the
//  TSan CI job for 15+ minutes on every PR. The race occurs when the next
//  test's setUp() calls FronteggApp.shared.manualInit() (which reassigns
//  featureFlags on the main thread) while a prior test's
//  startPostConnectivityServices() is still reading featureFlags on a GCD
//  worker. This test forces the race directly and asserts it does not occur
//  when -enableThreadSanitizer YES is set.
//

import XCTest
@testable import FronteggSwift

final class FronteggAuthFeatureFlagsRaceTests: XCTestCase {

    private let testBaseUrl = "https://test.frontegg.com"
    private let testClientId = "test-client"

    override func setUp() {
        super.setUp()
        PlistHelper.testConfigOverride = FronteggPlist(
            lateInit: true,
            payload: .singleRegion(
                .init(baseUrl: testBaseUrl, clientId: testClientId)
            ),
            keepUserLoggedInAfterReinstall: false
        )
        FronteggApp.shared.manualInit(
            baseUrl: testBaseUrl,
            cliendId: testClientId,
            applicationId: nil
        )
    }

    override func tearDown() {
        PlistHelper.testConfigOverride = nil
        super.tearDown()
    }

    func test_featureFlags_concurrentReassignmentAndRead_doesNotRace() async {
        // Direct repro: write on the main thread while reading from a
        // background thread, the same shape as manualInit (writer) vs
        // startPostConnectivityServices (reader) in production.
        let auth = FronteggAuth.shared
        let iterations = 10_000

        async let writer: Void = Task.detached {
            for _ in 0..<iterations {
                auth.featureFlags = FeatureFlags(
                    .init(clientId: "test-client", api: auth.api)
                )
            }
        }.value

        async let reader: Void = Task.detached {
            for _ in 0..<iterations {
                _ = auth.featureFlags
            }
        }.value

        _ = await (writer, reader)

        // The functional assertion: after all the churn, featureFlags is
        // still readable and yields a non-torn reference.
        XCTAssertNotNil(auth.featureFlags)
    }
}
