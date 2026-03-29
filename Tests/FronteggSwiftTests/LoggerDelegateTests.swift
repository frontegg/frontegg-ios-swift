//
//  LoggerDelegateTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

private final class SpyLoggerDelegate: FronteggLoggerDelegate {
    struct Event: Equatable {
        let message: String
        let level: FeLogger.Level
        let tag: String
    }

    private(set) var events: [Event] = []

    func fronteggSDK(didLog message: String, level: FeLogger.Level, tag: String) {
        events.append(.init(message: message, level: level, tag: tag))
    }
}

private final class ReentrantLoggerDelegate: FronteggLoggerDelegate {
    private let nestedLogger = FeLogger(label: "NestedLogger")
    private(set) var events: [SpyLoggerDelegate.Event] = []

    init() {
        nestedLogger.logLevel = .trace
    }

    func fronteggSDK(didLog message: String, level: FeLogger.Level, tag: String) {
        events.append(.init(message: message, level: level, tag: tag))
        nestedLogger.info("nested info log")
    }
}

final class LoggerDelegateTests: XCTestCase {

    override func setUp() {
        super.setUp()
        FeLogger.delegate = nil
    }

    override func tearDown() {
        FeLogger.delegate = nil
#if DEBUG
        PlistHelper.testConfigOverride = nil
#endif
        super.tearDown()
    }

    func test_delegateReceivesAllLevelsRegardlessOfLogLevelThreshold() {
        let spy = SpyLoggerDelegate()
        let logger = FeLogger(label: "ThresholdTest")
        logger.logLevel = .critical
        FeLogger.delegate = spy

        log("trace message", as: .trace, with: logger)
        log("debug message", as: .debug, with: logger)
        log("info message", as: .info, with: logger)
        log("warning message", as: .warning, with: logger)
        log("error message", as: .error, with: logger)
        log("critical message", as: .critical, with: logger)

        // Filter by tag to isolate from SDK singleton log noise (e.g. FronteggApp.shared
        // initialized by other tests emitting events via applicationDidBecomeActive)
        let relevant = spy.events.filter { $0.tag == "ThresholdTest" }
        XCTAssertEqual(
            relevant,
            [
                .init(message: "trace message", level: .trace, tag: "ThresholdTest"),
                .init(message: "debug message", level: .debug, tag: "ThresholdTest"),
                .init(message: "info message", level: .info, tag: "ThresholdTest"),
                .init(message: "warning message", level: .warning, tag: "ThresholdTest"),
                .init(message: "error message", level: .error, tag: "ThresholdTest"),
                .init(message: "critical message", level: .critical, tag: "ThresholdTest")
            ]
        )
    }

    func test_delegateCanBeConfiguredThroughFronteggAppAlias() {
#if DEBUG
        PlistHelper.testConfigOverride = makeSharedAppConfig()
#endif

        let spy = SpyLoggerDelegate()
        let app = FronteggApp.shared

        app.loggerDelegate = spy

        XCTAssertTrue(FeLogger.delegate as AnyObject? === spy)
        XCTAssertTrue(app.loggerDelegate as AnyObject? === spy)
    }

    func test_infoLevelDelegateRedactsSensitiveValues() {
        let message = """
        Callback URL: myapp://auth.example.com/ios/oauth/callback?code=abc123&state=state456, Authorization: Bearer top-secret, payload={"accessToken":"access-123","refreshToken":"refresh-456"}, User ID: user-123, Email: user@example.com
        """

        let event = captureSingleEvent(message, level: .info)

        XCTAssertEqual(
            event?.message,
            """
            Callback URL: myapp://auth.example.com/ios/oauth/callback?<redacted>, Authorization: Bearer <redacted>, payload={"accessToken":"<redacted>","refreshToken":"<redacted>"}, User ID: <redacted-user-id>, Email: <redacted-email>
            """
        )
        XCTAssertEqual(event?.level, .info)
        XCTAssertEqual(event?.tag, "RedactionTest")
    }

    func test_warningLevelDelegateRedactsCookieValuesButPreservesStatusCodes() {
        let message = "Cookie: fe_refresh_clientId=refresh-secret; Path=/, status code: 401"

        let event = captureSingleEvent(message, level: .warning)

        XCTAssertEqual(
            event?.message,
            "Cookie: fe_refresh_clientId=<redacted>; Path=/, status code: 401"
        )
    }

    func test_infoLevelDelegateRedactsOAuthParameterDumpButPreservesLengths() {
        let message = "  - code: abc123 (length: 6), Code length: 32, state: state-789"

        let event = captureSingleEvent(message, level: .info)

        XCTAssertEqual(
            event?.message,
            "  - code: <redacted> (length: 6), Code length: 32, state: <redacted>"
        )
    }

    func test_infoLevelDelegateRedactsCodeVerifierValueButNotMetadata() {
        let message = "Code verifier used (first 10 chars): abcdef1234, Code verifier source: webview_local_storage"

        let event = captureSingleEvent(message, level: .info)

        XCTAssertEqual(
            event?.message,
            "Code verifier used (first 10 chars): <redacted>, Code verifier source: webview_local_storage"
        )
    }

    func test_debugAndTraceDelegateMessagesRemainRaw() {
        let debugMessage = "Code verifier used (first 10 chars): abcdef1234"
        let traceMessage = "Callback URL: myapp://auth.example.com/ios/oauth/callback?code=abc123&state=state456"

        let debugEvent = captureSingleEvent(debugMessage, level: .debug)
        let traceEvent = captureSingleEvent(traceMessage, level: .trace)

        XCTAssertEqual(debugEvent?.message, debugMessage)
        XCTAssertEqual(traceEvent?.message, traceMessage)
    }

    func test_settingDelegateToNilStopsForwarding() {
        let spy = SpyLoggerDelegate()
        let logger = FeLogger(label: "NilDelegateTest")
        logger.logLevel = .trace
        FeLogger.delegate = spy

        logger.info("first message")
        FeLogger.delegate = nil
        logger.info("second message")

        XCTAssertEqual(
            spy.events,
            [.init(message: "first message", level: .info, tag: "NilDelegateTest")]
        )
    }

    func test_delegateWeakReferenceClearsAfterDeallocation() {
        let logger = FeLogger(label: "WeakDelegateTest")
        logger.logLevel = .trace
        weak var weakDelegate: SpyLoggerDelegate?

        do {
            let delegate = SpyLoggerDelegate()
            weakDelegate = delegate
            FeLogger.delegate = delegate
            XCTAssertNotNil(FeLogger.delegate)
        }

        XCTAssertNil(weakDelegate)
        XCTAssertNil(FeLogger.delegate)

        logger.info("post-deallocation message")
    }

    func test_reentrantDelegateDoesNotLoop() {
        let delegate = ReentrantLoggerDelegate()
        let logger = FeLogger(label: "OuterLogger")
        logger.logLevel = .trace
        FeLogger.delegate = delegate

        logger.info("outer info log")

        XCTAssertEqual(
            delegate.events,
            [.init(message: "outer info log", level: .info, tag: "OuterLogger")]
        )
    }

    private func captureSingleEvent(_ message: String, level: FeLogger.Level) -> SpyLoggerDelegate.Event? {
        let spy = SpyLoggerDelegate()
        let logger = FeLogger(label: "RedactionTest")
        logger.logLevel = .error
        FeLogger.delegate = spy

        log(message, as: level, with: logger)

        return spy.events.last
    }

    private func log(_ message: String, as level: FeLogger.Level, with logger: FeLogger) {
        switch level {
        case .trace:
            logger.trace(message)
        case .debug:
            logger.debug(message)
        case .info:
            logger.info(message)
        case .warning:
            logger.warning(message)
        case .error:
            logger.error(message)
        case .critical:
            logger.critical(message)
        }
    }

    private func makeSharedAppConfig() -> FronteggPlist {
        FronteggPlist(
            lateInit: true,
            payload: .singleRegion(
                .init(
                    baseUrl: "https://test.example.com",
                    clientId: "test-client-id"
                )
            ),
            keepUserLoggedInAfterReinstall: true,
            useAsWebAuthenticationForAppleLogin: false
        )
    }
}
