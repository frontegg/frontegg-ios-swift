import XCTest
import AuthenticationServices
@testable import FronteggSwift

final class FronteggErrorCategoryTests: XCTestCase {

    func test_configError_isConfiguration() {
        XCTAssertEqual(FronteggError.configError(.missingPlist).category, .configuration)
        XCTAssertEqual(FronteggError.configError(.socialLoginMissing("apple")).category, .configuration)
    }

    func test_networkError_isNetwork() {
        XCTAssertEqual(FronteggError.networkError(.unknown).category, .network)
    }

    func test_authError_mapping() {
        let expected: [(FronteggError.Authentication, FronteggErrorCategory)] = [
            (.operationCanceled, .cancelled),
            (.mfaRequired([:]), .mfaRequired),
            (.failedToSwitchTenant, .tenantSwitchFailed),
            (.notAuthenticated, .notAuthenticated),
            (.failedToRefreshToken("expired"), .notAuthenticated),
            (.invalidResponse, .invalidResponse),
            (.failedToExtractCode, .invalidResponse),
            (.couldNotFindRootViewController, .configuration),
            (.failedToAuthenticate, .authenticationFailed),
            (.couldNotExchangeToken("bad code"), .authenticationFailed),
            (.failedToLoadUserData("nil"), .authenticationFailed),
            (.failedToMFA, .authenticationFailed),
            (.codeVerifierNotFound, .authenticationFailed),
            (.invalidOAuthState, .authenticationFailed),
            (.invalidPasskeysRequest, .authenticationFailed),
            (.failedToAuthenticateWithPasskeys("x"), .authenticationFailed),
            (.oauthError("access_denied"), .authenticationFailed),
            (.unknown, .unknown),
        ]
        for (error, category) in expected {
            XCTAssertEqual(FronteggError.authError(error).category, category, "\(error)")
            XCTAssertEqual(error.category, category, "\(error)")
        }
    }

    func test_other_classifiesUnderlyingError() {
        XCTAssertEqual(FronteggError.authError(.other(URLError(.notConnectedToInternet))).category, .network)
        XCTAssertEqual(FronteggError.authError(.other(URLError(.timedOut))).category, .network)
        XCTAssertEqual(FronteggError.authError(.other(URLError(.cancelled))).category, .cancelled)
        XCTAssertEqual(FronteggError.authError(.other(URLError(.badServerResponse))).category, .invalidResponse)
        XCTAssertEqual(FronteggError.authError(.other(FronteggError.authError(.failedToSwitchTenant))).category, .tenantSwitchFailed)
        XCTAssertEqual(FronteggError.authError(.other(NSError(domain: "x", code: 1))).category, .unknown)
    }

    func test_arbitraryErrors() {
        XCTAssertEqual(FronteggErrorCategory(URLError(.networkConnectionLost)), .network)
        XCTAssertEqual(FronteggErrorCategory(CancellationError()), .cancelled)
        XCTAssertEqual(
            FronteggErrorCategory(ASWebAuthenticationSessionError(.canceledLogin)),
            .cancelled
        )
        XCTAssertEqual(
            FronteggErrorCategory(ASWebAuthenticationSessionError(.presentationContextNotProvided)),
            .configuration
        )
        XCTAssertEqual(FronteggErrorCategory(ASAuthorizationError(.canceled)), .cancelled)
        XCTAssertEqual(FronteggErrorCategory(ASAuthorizationError(.failed)), .authenticationFailed)
        XCTAssertEqual(
            FronteggErrorCategory(NSError(domain: NSPOSIXErrorDomain, code: Int(POSIXError.ECONNRESET.rawValue))),
            .network
        )
        let decodingError = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad"))
        XCTAssertEqual(FronteggErrorCategory(decodingError), .invalidResponse)
        XCTAssertEqual(FronteggErrorCategory(NSError(domain: "x", code: 1)), .unknown)
    }

    func test_httpStatusErrors() {
        XCTAssertEqual(
            FronteggErrorCategory(ApiError.refreshEndpointTransient(statusCode: 503, message: "")),
            .server(statusCode: 503)
        )
        XCTAssertEqual(
            FronteggErrorCategory(ApiError.meEndpointFailed(statusCode: 502, path: "me")),
            .server(statusCode: 502)
        )
        XCTAssertEqual(
            FronteggErrorCategory(ApiError.meEndpointFailed(statusCode: 401, path: "me")),
            .notAuthenticated
        )
        XCTAssertEqual(FronteggErrorCategory(ApiError.invalidUrl("x")), .configuration)
    }

    func test_nestedFronteggErrors() {
        XCTAssertEqual(FronteggErrorCategory(FronteggError.authError(.operationCanceled)), .cancelled)
        XCTAssertEqual(FronteggErrorCategory(FronteggError.Authentication.mfaRequired([:])), .mfaRequired)
        XCTAssertEqual(FronteggErrorCategory(FronteggError.Configuration.missingRegions), .configuration)
    }

    func test_code_isStable() {
        XCTAssertEqual(FronteggErrorCategory.network.code, "network")
        XCTAssertEqual(FronteggErrorCategory.cancelled.code, "cancelled")
        XCTAssertEqual(FronteggErrorCategory.mfaRequired.code, "mfaRequired")
        XCTAssertEqual(FronteggErrorCategory.tenantSwitchFailed.code, "tenantSwitchFailed")
        XCTAssertEqual(FronteggErrorCategory.notAuthenticated.code, "notAuthenticated")
        XCTAssertEqual(FronteggErrorCategory.authenticationFailed.code, "authenticationFailed")
        XCTAssertEqual(FronteggErrorCategory.configuration.code, "configuration")
        XCTAssertEqual(FronteggErrorCategory.invalidResponse.code, "invalidResponse")
        XCTAssertEqual(FronteggErrorCategory.server(statusCode: 500).code, "server")
        XCTAssertEqual(FronteggErrorCategory.unknown.code, "unknown")
    }

    func test_from_preservesFronteggErrors() {
        let original = FronteggError.authError(.failedToSwitchTenant)
        guard case .authError(.failedToSwitchTenant) = FronteggError.from(original) else {
            return XCTFail("FronteggError must pass through unchanged")
        }
        guard case .configError(.missingPlist) = FronteggError.from(FronteggError.Configuration.missingPlist) else {
            return XCTFail("Configuration must be wrapped in configError")
        }
        guard case .authError(.operationCanceled) = FronteggError.from(FronteggError.Authentication.operationCanceled) else {
            return XCTFail("Authentication must be wrapped in authError")
        }
    }

    func test_from_wrapsForeignErrorsWithoutLosingCause() {
        let wrapped = FronteggError.from(URLError(.notConnectedToInternet))
        guard case .authError(.other(let underlying)) = wrapped else {
            return XCTFail("foreign errors must be wrapped in .other, got \(wrapped)")
        }
        XCTAssertEqual((underlying as? URLError)?.code, .notConnectedToInternet)
        XCTAssertEqual(wrapped.category, .network)
        XCTAssertEqual((wrapped.underlyingError as? URLError)?.code, .notConnectedToInternet)
        XCTAssertEqual(wrapped.errorDescription, URLError(.notConnectedToInternet).localizedDescription)
    }

    func test_underlyingError_nilForNonWrappedCases() {
        XCTAssertNil(FronteggError.authError(.failedToAuthenticate).underlyingError)
        XCTAssertNil(FronteggError.configError(.missingPlist).underlyingError)
    }

    func test_failureReason_unchangedForWrappers() {
        XCTAssertEqual(FronteggError.Authentication.failedToSwitchTenant.failureReason, "failedToSwitchTenant")
        XCTAssertEqual(FronteggError.Authentication.other(URLError(.timedOut)).failureReason, "other")
    }
}
