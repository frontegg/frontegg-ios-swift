import Foundation

enum FronteggRuntime {
    static let testingEnvironmentKey = "frontegg-testing"
    static let testingWebAuthenticationTransportEnvironmentKey = "FRONTEGG_TEST_WEB_AUTH_TRANSPORT"

    static var isTesting: Bool {
        ProcessInfo.processInfo.environment[testingEnvironmentKey] == "true"
    }

    static func testingLog(_ message: @autoclosure () -> String) {
#if DEBUG
        guard isTesting else { return }
        print(message())
#endif
    }

    static var allowsTestingWebAuthenticationTransport: Bool {
#if DEBUG
        return ProcessInfo.processInfo.environment[testingWebAuthenticationTransportEnvironmentKey] == "1"
#else
        return false
#endif
    }

    static func socialAuthorizeEndpointOverride(provider: String) -> String? {
#if DEBUG
        guard isTesting else { return nil }
        let key = "FRONTEGG_TEST_SOCIAL_AUTHORIZE_URL_\(provider.uppercased())"
        return ProcessInfo.processInfo.environment[key]
#else
        return nil
#endif
    }
}
