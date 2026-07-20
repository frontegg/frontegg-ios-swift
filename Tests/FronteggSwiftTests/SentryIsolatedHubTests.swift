//
//  SentryIsolatedHubTests.swift
//  FronteggSwiftTests
//
//  FR-25990: the SDK must report through an isolated Sentry hub, never the global
//  SentrySDK. Starting the global client binds it to Frontegg's DSN and hijacks a
//  host app that runs its own Sentry.
//

import XCTest
import Sentry
@testable import FronteggSwift

final class SentryIsolatedHubTests: XCTestCase {

    override func setUp() {
        super.setUp()
        SentryHelper.resetForTesting()
    }

    override func tearDown() {
        SentryHelper.setSentryEnabledFromFeatureFlag(false)
        SentryHelper.resetForTesting()
        super.tearDown()
    }

    func test_initialize_doesNotStartGlobalSentrySDK() {
        XCTAssertFalse(
            SentrySDK.isEnabled,
            "precondition: the global Sentry client must be off before Frontegg initializes"
        )

        SentryHelper.setSentryEnabledFromFeatureFlag(true)
        SentryHelper.initialize()

        XCTAssertFalse(
            SentrySDK.isEnabled,
            "Frontegg must report through an isolated Sentry hub — starting the global SentrySDK hijacks the host app's own DSN"
        )
    }
}
