import XCTest
import AuthenticationServices
@testable import FronteggSwift

/// Covers FR-26003: the native passkey *registration* flow must deliver its
/// completion when `verifyNewDeviceSession` resolves — even though the
/// ASAuthorization delegate has already cleared `callbackAction` by then.
@available(iOS 15.0, *)
final class PasskeysRegistrationCompletionTests: XCTestCase {

    private func makeRegistration() -> WebauthnRegistration {
        WebauthnRegistration(
            id: "credential-id",
            response: WebauthnRegistrationResponse(
                clientDataJSON: "client-data",
                attestationObject: "attestation"
            )
        )
    }

    /// A successful (empty-body 2xx) verify must fire the registration
    /// completion, regardless of `callbackAction` having been nil'd by the
    /// delegate. This is the exact drop the bug caused.
    func testVerifySuccessDeliversRegistrationCompletion() async {
        let authenticator = PasskeysAuthenticator()

        let completed = expectation(description: "registration completion invoked")
        var receivedError: FronteggError? = FronteggError.authError(.unknown)
        authenticator.registrationCompletion = { error in
            receivedError = error
            completed.fulfill()
        }

        let transport: PasskeysAuthenticator.VerifyTransport = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://example.frontegg.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
            return (Data(), response, nil)
        }

        await authenticator.verifyNewDeviceSession(
            publicKey: makeRegistration(),
            baseUrl: "https://example.frontegg.com",
            accessToken: "access-token",
            verifyTransport: transport
        )

        await fulfillment(of: [completed], timeout: 2.0)
        XCTAssertNil(receivedError, "successful verify should complete with no error")
    }

    /// A transport error must propagate to the registration completion, not be
    /// silently dropped.
    func testVerifyFailureDeliversRegistrationCompletion() async {
        let authenticator = PasskeysAuthenticator()

        let completed = expectation(description: "registration completion invoked")
        var receivedError: FronteggError?
        authenticator.registrationCompletion = { error in
            receivedError = error
            completed.fulfill()
        }

        let transport: PasskeysAuthenticator.VerifyTransport = { _ in
            (nil, nil, FronteggError.authError(.failedToAuthenticate))
        }

        await authenticator.verifyNewDeviceSession(
            publicKey: makeRegistration(),
            baseUrl: "https://example.frontegg.com",
            accessToken: "access-token",
            verifyTransport: transport
        )

        await fulfillment(of: [completed], timeout: 2.0)
        XCTAssertNotNil(receivedError, "failed verify should complete with an error")
    }
}

@available(iOS 15.0, *)
final class PasskeysRegistrationCancellationTests: XCTestCase {

    private func deliver(_ error: Error?) -> FronteggError? {
        let authenticator = PasskeysAuthenticator()
        var received: FronteggError?
        var called = false
        authenticator.registrationCompletion = { error in
            received = error
            called = true
        }
        authenticator.handleRegistrationCallback(data: nil, error: error)
        XCTAssertTrue(called)
        return received
    }

    func testUserCancelledRegistrationCompletesWithOperationCanceled() {
        let received = deliver(ASAuthorizationError(.canceled))

        guard case .authError(.operationCanceled)? = received else {
            return XCTFail("expected operationCanceled, got \(String(describing: received))")
        }
    }

    func testNonCancelAuthorizationFailureIsNotReportedAsCancel() {
        let received = deliver(ASAuthorizationError(.failed))

        XCTAssertNotNil(received)
        if case .authError(.operationCanceled)? = received {
            XCTFail("a failed authorization must not be reported as a cancel")
        }
    }

    func testFronteggErrorIsPassedThrough() {
        let received = deliver(FronteggError.authError(.invalidPasskeysRequest))

        guard case .authError(.invalidPasskeysRequest)? = received else {
            return XCTFail("expected invalidPasskeysRequest, got \(String(describing: received))")
        }
    }
}
