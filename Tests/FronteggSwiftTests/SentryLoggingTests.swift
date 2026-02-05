//
//  SentryLoggingTests.swift
//  FronteggSwiftTests
//
//  Verifies that Sentry logging is gated by the mobile-enable-logging feature flag.
//

import XCTest
@testable import FronteggSwift

final class SentryLoggingTests: XCTestCase {

    override func tearDown() {
        // Reset feature flag state so other tests or app code see a clean state
        SentryHelper.setSentryEnabledFromFeatureFlag(false)
        super.tearDown()
    }

    // MARK: - Feature flag key

    func test_mobileEnableLoggingKey_matchesSentryGating() {
        XCTAssertEqual(
            FeatureFlags.mobileEnableLoggingKey,
            "mobile-enable-logging",
            "Sentry is enabled only when this feature flag is on; key must match backend"
        )
    }

    // MARK: - SentryHelper gated by feature flag

    func test_setSentryEnabledFromFeatureFlag_false_disablesSentryReporting() {
        SentryHelper.setSentryEnabledFromFeatureFlag(true)
        XCTAssertTrue(SentryHelper.sentryEnabledByFeatureFlagForTesting() == true)

        SentryHelper.setSentryEnabledFromFeatureFlag(false)
        XCTAssertTrue(
            SentryHelper.sentryEnabledByFeatureFlagForTesting() == false,
            "When mobile-enable-logging is off, Sentry reporting must be disabled"
        )
    }

    func test_setSentryEnabledFromFeatureFlag_true_allowsSentryReporting() {
        SentryHelper.setSentryEnabledFromFeatureFlag(false)
        XCTAssertTrue(SentryHelper.sentryEnabledByFeatureFlagForTesting() == false)

        SentryHelper.setSentryEnabledFromFeatureFlag(true)
        XCTAssertTrue(
            SentryHelper.sentryEnabledByFeatureFlagForTesting() == true,
            "When mobile-enable-logging is on, Sentry reporting may be enabled (if Sentry is initialized)"
        )
    }

    func test_sentryEnabledByFeatureFlag_startsNilOrFalse_afterExplicitFalse() {
        SentryHelper.setSentryEnabledFromFeatureFlag(false)
        let value = SentryHelper.sentryEnabledByFeatureFlagForTesting()
        XCTAssertTrue(value == false || value == nil, "Sentry must not report when flag is false or unset")
    }

    func test_logError_withFeatureFlagFalse_doesNotCrash() {
        SentryHelper.setSentryEnabledFromFeatureFlag(false)
        SentryHelper.logError(NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "test"]))
        // When flag is false, isSentryEnabled() is false so capture is skipped; no crash
    }

    func test_logMessage_withFeatureFlagFalse_doesNotCrash() {
        SentryHelper.setSentryEnabledFromFeatureFlag(false)
        SentryHelper.logMessage("test message", level: .info)
        // When flag is false, isSentryEnabled() is false so capture is skipped; no crash
    }
}
