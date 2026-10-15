import XCTest
@testable import FronteggSwift

final class FronteggSecurityAPITests: XCTestCase {

    private let baseUrl = "https://auth.example.com"

    private final class RecordingTransport {
        var requests: [URLRequest] = []
        var statusCode = 200
        var body = Data()
        var error: Error?

        func handle(_ request: URLRequest) async throws -> (Data, URLResponse) {
            requests.append(request)
            if let error { throw error }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (body, response)
        }
    }

    private func makeAPI(
        transport: RecordingTransport,
        token: String? = "access-token",
        applicationId: String? = nil
    ) -> FronteggSecurityAPI {
        FronteggSecurityAPI(
            baseUrl: baseUrl,
            applicationId: applicationId,
            accessTokenProvider: { token },
            transport: { try await transport.handle($0) }
        )
    }

    func testListSessionsCallsCurrentUserSessionsEndpointAndDecodes() async throws {
        let transport = RecordingTransport()
        transport.body = Data("""
        [
          {"id": "s1", "ipAddress": "10.0.0.1", "userAgent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", "createdAt": "2026-01-02T03:04:05.678Z", "expires": "2026-02-02T03:04:05Z", "current": true, "impersonated": false},
          {"id": "s2", "createdAt": "2026-01-01T00:00:00Z"}
        ]
        """.utf8)

        let sessions = try await makeAPI(transport: transport, applicationId: "app-1").listSessions()

        XCTAssertEqual(transport.requests.count, 1)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "\(baseUrl)/frontegg/identity/resources/users/sessions/v1/me")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), baseUrl)
        XCTAssertEqual(request.value(forHTTPHeaderField: "frontegg-requested-application-id"), "app-1")

        XCTAssertEqual(sessions.map(\.id), ["s1", "s2"])
        XCTAssertEqual(sessions[0].ipAddress, "10.0.0.1")
        XCTAssertTrue(sessions[0].isCurrent)
        XCTAssertFalse(sessions[0].isImpersonated)
        XCTAssertNotNil(sessions[0].createdAt)
        XCTAssertNotNil(sessions[0].expires)
        XCTAssertNotNil(sessions[1].createdAt)
        XCTAssertFalse(sessions[1].isCurrent)
        XCTAssertNil(sessions[1].userAgent)
    }

    func testListSessionsMarksSessionMatchingAccessTokenSidAsCurrent() async throws {
        let transport = RecordingTransport()
        transport.body = Data(#"[{"id": "s1"}, {"id": "s2"}]"#.utf8)
        let token = try TestDataFactory.makeJWT(payloadDict: ["sid": "s2"])

        let sessions = try await makeAPI(transport: transport, token: token).listSessions()

        XCTAssertEqual(sessions.filter(\.isCurrent).map(\.id), ["s2"])
    }

    func testRevokeSessionSendsDeleteToSessionPath() async throws {
        let transport = RecordingTransport()
        transport.statusCode = 204

        try await makeAPI(transport: transport).revokeSession(id: "abc-123")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.absoluteString, "\(baseUrl)/frontegg/identity/resources/users/sessions/v1/me/abc-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
    }

    func testRevokeOtherSessionsSendsDeleteToAllPath() async throws {
        let transport = RecordingTransport()

        try await makeAPI(transport: transport).revokeOtherSessions()

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.absoluteString, "\(baseUrl)/frontegg/identity/resources/users/sessions/v1/me/all")
    }

    func testRevokeSessionPercentEncodesId() async throws {
        let transport = RecordingTransport()

        try await makeAPI(transport: transport).revokeSession(id: "a/b c")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "\(baseUrl)/frontegg/identity/resources/users/sessions/v1/me/a%2Fb%20c")
    }

    func testListPasskeysCallsWebAuthnDevicesEndpointAndDecodes() async throws {
        let transport = RecordingTransport()
        transport.body = Data("""
        {"devices": [
          {"id": "d1", "deviceType": "Platform", "createdAt": "2026-03-04T05:06:07.000Z"},
          {"id": "d2", "deviceType": "CrossPlatform"}
        ]}
        """.utf8)

        let passkeys = try await makeAPI(transport: transport).listPasskeys()

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "\(baseUrl)/frontegg/identity/resources/users/webauthn/v1/devices")
        XCTAssertEqual(passkeys.map(\.id), ["d1", "d2"])
        XCTAssertEqual(passkeys[0].deviceType, .platform)
        XCTAssertEqual(passkeys[1].deviceType, .crossPlatform)
        XCTAssertNotNil(passkeys[0].createdAt)
        XCTAssertNil(passkeys[1].createdAt)
    }

    func testUnknownPasskeyDeviceTypeDecodesAsOther() async throws {
        let transport = RecordingTransport()
        transport.body = Data(#"{"devices": [{"id": "d1", "deviceType": "Hybrid"}]}"#.utf8)

        let passkeys = try await makeAPI(transport: transport).listPasskeys()

        XCTAssertEqual(passkeys.first?.deviceType, .other("Hybrid"))
    }

    func testDeletePasskeySendsDeleteToDevicePath() async throws {
        let transport = RecordingTransport()

        try await makeAPI(transport: transport).deletePasskey(id: "d1")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.absoluteString, "\(baseUrl)/frontegg/identity/resources/users/webauthn/v1/devices/d1")
    }

    func testNon2xxStatusThrowsRequestFailedWithStatusCode() async {
        let transport = RecordingTransport()
        transport.statusCode = 403

        do {
            try await makeAPI(transport: transport).revokeSession(id: "s1")
            XCTFail("expected an error")
        } catch let error as FronteggSecurityCenterError {
            XCTAssertEqual(error, .requestFailed(statusCode: 403))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testMissingAccessTokenThrowsNotAuthenticatedWithoutSendingRequest() async {
        let transport = RecordingTransport()

        do {
            _ = try await makeAPI(transport: transport, token: nil).listSessions()
            XCTFail("expected an error")
        } catch let error as FronteggSecurityCenterError {
            XCTAssertEqual(error, .notAuthenticated)
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testMalformedBodyThrowsInvalidResponse() async {
        let transport = RecordingTransport()
        transport.body = Data("not json".utf8)

        do {
            _ = try await makeAPI(transport: transport).listPasskeys()
            XCTFail("expected an error")
        } catch let error as FronteggSecurityCenterError {
            XCTAssertEqual(error, .invalidResponse)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testTransportErrorPropagates() async {
        let transport = RecordingTransport()
        transport.error = URLError(.notConnectedToInternet)

        do {
            _ = try await makeAPI(transport: transport).listSessions()
            XCTFail("expected an error")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testSessionIdIsReadFromAccessTokenSidClaim() throws {
        let token = try TestDataFactory.makeJWT(payloadDict: ["sid": "session-42", "sub": "user"])

        XCTAssertEqual(FronteggSecurityAPI.sessionId(fromAccessToken: token), "session-42")
        XCTAssertNil(FronteggSecurityAPI.sessionId(fromAccessToken: "not-a-jwt"))
    }

    func testSessionPlatformIsDerivedFromUserAgent() {
        func session(_ userAgent: String?) -> FronteggSession {
            FronteggSession(id: "x", userAgent: userAgent)
        }
        XCTAssertEqual(session("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) Safari").platform, .iPhone)
        XCTAssertEqual(session("Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X)").platform, .iPad)
        XCTAssertEqual(session("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) Chrome/120").platform, .mac)
        XCTAssertEqual(session("Mozilla/5.0 (Linux; Android 14; Pixel 8)").platform, .android)
        XCTAssertEqual(session("Mozilla/5.0 (Windows NT 10.0; Win64; x64)").platform, .windows)
        XCTAssertEqual(session("Mozilla/5.0 (X11; Linux x86_64)").platform, .linux)
        XCTAssertEqual(session("demo/1 CFNetwork/1490 Darwin/23.0.0").platform, .unknown)
        XCTAssertEqual(session(nil).platform, .unknown)
    }
}
