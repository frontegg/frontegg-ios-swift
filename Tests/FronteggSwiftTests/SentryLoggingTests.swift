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

    func test_shouldDropErrorForTesting_dropsApiError502And503() {
        XCTAssertTrue(
            SentryHelper.shouldDropErrorForTesting(ApiError.meEndpointFailed(statusCode: 502, path: "/me"))
        )
        XCTAssertTrue(
            SentryHelper.shouldDropErrorForTesting(ApiError.meEndpointFailed(statusCode: 503, path: "/me"))
        )
        XCTAssertTrue(
            SentryHelper.shouldDropErrorForTesting(ApiError.refreshEndpointTransient(statusCode: 502, message: "temporary"))
        )
    }

    func test_shouldDropErrorForTesting_keepsOtherStatusCodes() {
        XCTAssertFalse(
            SentryHelper.shouldDropErrorForTesting(ApiError.meEndpointFailed(statusCode: 500, path: "/me"))
        )
        XCTAssertFalse(
            SentryHelper.shouldDropErrorForTesting(ApiError.meEndpointFailed(statusCode: 504, path: "/me"))
        )
    }

    func test_shouldDropErrorForTesting_dropsWhenHttpContextHas502Or503() {
        let generic = NSError(domain: "test", code: -1)
        XCTAssertTrue(
            SentryHelper.shouldDropErrorForTesting(
                generic,
                context: ["http": ["statusCode": 502]]
            )
        )
        XCTAssertTrue(
            SentryHelper.shouldDropErrorForTesting(
                generic,
                context: ["http": ["statusCode": 503]]
            )
        )
    }

    // MARK: - Breadcrumb payload sanitization

    func test_sanitizeBreadcrumbPayload_stripsQueryFromUrls() {
        let raw = [
            "url": "https://example.com/oauth/callback?code=secret123&state=abc"
        ]
        let out = SentryHelper.sanitizeBreadcrumbPayloadForTesting(raw)
        XCTAssertEqual(out["url"] as? String, "https://example.com/oauth/callback")
    }

    func test_sanitizeBreadcrumbPayload_redactsSensitiveKeys() {
        let raw: [String: Any] = [
            "Authorization": "Bearer x",
            "x-amz-security-token": "tok",
            "safe": "ok"
        ]
        let out = SentryHelper.sanitizeBreadcrumbPayloadForTesting(raw)
        XCTAssertEqual(out["Authorization"] as? String, "[redacted]")
        XCTAssertEqual(out["x-amz-security-token"] as? String, "[redacted]")
        XCTAssertEqual(out["safe"] as? String, "ok")
    }

    func test_sanitizeBreadcrumbPayload_redactsHttpQueryFragmentKeys() {
        let raw: [String: Any] = [
            "http.query": "token=1",
            "http.fragment": "frag"
        ]
        let out = SentryHelper.sanitizeBreadcrumbPayloadForTesting(raw)
        XCTAssertEqual(out["http.query"] as? String, "[redacted]")
        XCTAssertEqual(out["http.fragment"] as? String, "[redacted]")
    }

    func test_sanitizeBreadcrumbPayload_redactsPkceAndWebAuthnStyleKeys() {
        let raw: [String: Any] = [
            "code_verifier": "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
            "clientDataJSON": "{\"type\":\"webauthn.get\"}",
            "challenge": "binary-challenge-material",
            "userHandle": "dXNlcg"
        ]
        let out = SentryHelper.sanitizeBreadcrumbPayloadForTesting(raw)
        XCTAssertEqual(out["code_verifier"] as? String, "[redacted]")
        XCTAssertEqual(out["clientDataJSON"] as? String, "[redacted]")
        XCTAssertEqual(out["challenge"] as? String, "[redacted]")
        XCTAssertEqual(out["userHandle"] as? String, "[redacted]")
    }

    func test_sanitizeBreadcrumbPayload_stripsQueryFromLocationHeaderValue() {
        let raw = [
            "location": "https://idp.example.com/callback?code=abc&session_state=xyz"
        ]
        let out = SentryHelper.sanitizeBreadcrumbPayloadForTesting(raw)
        XCTAssertEqual(out["location"] as? String, "https://idp.example.com/callback")
    }

    // MARK: - Breadcrumb gating by logLevel
    //
    // Regression coverage for "Sentry quota exhausted" — pre-fix, `addBreadcrumb`
    // ignored the configured `logLevel` and shipped every `info`/`debug` breadcrumb,
    // so a host app that set `logLevel: warn` to silence the SDK still saw the SDK
    // flood Sentry. The gate now mirrors `FeLogger.emit`: emit when the configured
    // threshold <= the breadcrumb's level.

    func test_breadcrumbGating_atDefaultWarningLevel_dropsInfoAndDebug() {
        // Default configured logLevel is `.warning` (rawValue 3).
        PlistHelper.resetLogLevelCacheForTesting()

        XCTAssertFalse(
            SentryHelper.breadcrumbMeetsLogLevelThresholdForTesting(.debug),
            ".debug breadcrumb must be dropped when logLevel is .warning"
        )
        XCTAssertFalse(
            SentryHelper.breadcrumbMeetsLogLevelThresholdForTesting(.info),
            ".info breadcrumb must be dropped when logLevel is .warning — this is the actual bug fix"
        )
    }

    func test_breadcrumbGating_atDefaultWarningLevel_emitsWarningAndAbove() {
        PlistHelper.resetLogLevelCacheForTesting()

        XCTAssertTrue(
            SentryHelper.breadcrumbMeetsLogLevelThresholdForTesting(.warning),
            ".warning breadcrumb must still ship at the default .warning logLevel"
        )
        XCTAssertTrue(
            SentryHelper.breadcrumbMeetsLogLevelThresholdForTesting(.error),
            ".error breadcrumb must still ship at the default .warning logLevel"
        )
        XCTAssertTrue(
            SentryHelper.breadcrumbMeetsLogLevelThresholdForTesting(.fatal),
            ".fatal breadcrumb must still ship at the default .warning logLevel"
        )
    }

    func test_breadcrumbGating_alwaysDropsSentryLevelNone() {
        PlistHelper.resetLogLevelCacheForTesting()

        XCTAssertFalse(
            SentryHelper.breadcrumbMeetsLogLevelThresholdForTesting(.none),
            "SentryLevel.none must never emit a breadcrumb"
        )
    }
}
