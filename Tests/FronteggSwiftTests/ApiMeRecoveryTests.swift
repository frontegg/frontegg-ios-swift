//
//  ApiMeRecoveryTests.swift
//  FronteggSwiftTests
//
//  Verifies /me and /me/tenants recovery paths for structural tenant payload issues.
//

import XCTest
@testable import FronteggSwift

private final class MockMeRecoveryApi: Api {
    private(set) var refreshCallCount = 0
    var refreshResults: [Result<AuthResponse, Error>] = []
    var responseQueues: [String: [(statusCode: Int, data: Data, error: Error?)]] = [:]
    var callCounts: [String: Int] = [:]

    init() {
        super.init(baseUrl: "https://test.example.com", clientId: "test-client", applicationId: nil)
    }

    override func refreshToken(
        refreshToken: String,
        tenantId: String? = nil,
        accessToken: String? = nil
    ) async throws -> AuthResponse {
        refreshCallCount += 1
        guard !refreshResults.isEmpty else {
            throw ApiError.invalidUrl("Missing refresh result")
        }

        switch refreshResults.removeFirst() {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }

    override func sleepBeforeRetry(attempt: Int) async {
        // Structural recovery tests should not wait on backoff delays.
    }

    override func getRequest(
        path: String,
        accessToken: String?,
        refreshToken: String? = nil,
        additionalHeaders: [String: String] = [:],
        followRedirect: Bool = true,
        timeout: Int = Api.DEFAULT_TIMEOUT,
        retries: Int = 0
    ) async throws -> (Data, URLResponse) {
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        callCounts[normalizedPath, default: 0] += 1

        guard var queue = responseQueues[normalizedPath], !queue.isEmpty else {
            throw ApiError.invalidUrl("No mock response for path: \(normalizedPath)")
        }

        let entry = queue.removeFirst()
        responseQueues[normalizedPath] = queue

        if let error = entry.error {
            if retries > 0, let nextQueue = responseQueues[normalizedPath], !nextQueue.isEmpty {
                return try await getRequest(
                    path: path,
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    additionalHeaders: additionalHeaders,
                    followRedirect: followRedirect,
                    timeout: timeout,
                    retries: retries - 1
                )
            }
            throw error
        }

        let url = URL(string: "https://test.example.com/\(normalizedPath)")!
        let httpResponse = HTTPURLResponse(url: url, statusCode: entry.statusCode, httpVersion: nil, headerFields: nil)!

        if entry.statusCode == 401 {
            throw ApiError.meEndpointFailed(statusCode: 401, path: path)
        }

        if Api.isTransientRefreshHTTPStatus(entry.statusCode) {
            if retries > 0, let nextQueue = responseQueues[normalizedPath], !nextQueue.isEmpty {
                return try await getRequest(
                    path: path,
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    additionalHeaders: additionalHeaders,
                    followRedirect: followRedirect,
                    timeout: timeout,
                    retries: retries - 1
                )
            }
            throw ApiError.meEndpointFailed(statusCode: entry.statusCode, path: path)
        }

        return (entry.data, httpResponse)
    }

    func enqueueJSON(path: String, statusCode: Int, json: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        responseQueues[path, default: []].append((statusCode: statusCode, data: data, error: nil))
    }
}

final class ApiMeRecoveryTests: XCTestCase {
    private let mePath = "identity/resources/users/v2/me"
    private let tenantsPath = "identity/resources/users/v3/me/tenants"

    private var api: MockMeRecoveryApi!

    override func setUp() {
        super.setUp()
        api = MockMeRecoveryApi()
    }

    override func tearDown() {
        api = nil
        super.tearDown()
    }

    func test_me_tenantsErrorPayload_thenValidTenants_recoversOnStructureRetry() async throws {
        api.enqueueJSON(path: mePath, statusCode: 200, json: makeUserResponse(email: "retry@example.com"))
        api.enqueueJSON(path: tenantsPath, statusCode: 200, json: ["errors": [["message": "ER-00004"]]])
        api.enqueueJSON(path: tenantsPath, statusCode: 200, json: makeTenantsResponse())

        let result = try await api.me(accessToken: "access-token", refreshToken: "refresh-token")

        XCTAssertEqual(result.user?.email, "retry@example.com")
        XCTAssertNil(result.refreshedTokens)
        XCTAssertEqual(api.callCounts[mePath], 1)
        XCTAssertEqual(api.callCounts[tenantsPath], 2)
        XCTAssertEqual(api.refreshCallCount, 0)
    }

    func test_me_invalidTenantsPayload_afterRerefresh_returnsRefreshedTokens() async throws {
        api.enqueueJSON(path: mePath, statusCode: 200, json: makeUserResponse(email: "initial@example.com", tenantId: "tenant-old"))
        api.enqueueJSON(path: tenantsPath, statusCode: 200, json: ["errors": [["message": "ER-00004"]]])
        api.enqueueJSON(path: tenantsPath, statusCode: 200, json: ["error": "still pending"])
        api.enqueueJSON(path: tenantsPath, statusCode: 200, json: makeTenantsResponse(tenantId: "tenant-new"))
        api.enqueueJSON(path: mePath, statusCode: 200, json: makeUserResponse(email: "corrected@example.com", tenantId: "tenant-new"))
        api.refreshResults = [
            .success(try makeAuthResponse(accessToken: "rotated-access-token", refreshToken: "rotated-refresh-token"))
        ]

        let result = try await api.me(accessToken: "access-token", refreshToken: "refresh-token")

        XCTAssertEqual(result.user?.email, "corrected@example.com")
        XCTAssertEqual(result.refreshedTokens?.access_token, "rotated-access-token")
        XCTAssertEqual(result.refreshedTokens?.refresh_token, "rotated-refresh-token")
        XCTAssertEqual(api.callCounts[mePath], 2)
        XCTAssertEqual(api.callCounts[tenantsPath], 3)
        XCTAssertEqual(api.refreshCallCount, 1)
    }

    func test_me_invalidTenantsPayload_afterRerefreshStillInvalid_throwsMeEndpointFailed0() async throws {
        api.enqueueJSON(path: mePath, statusCode: 200, json: makeUserResponse())
        api.enqueueJSON(path: tenantsPath, statusCode: 200, json: ["errors": [["message": "ER-00004"]]])
        api.enqueueJSON(path: tenantsPath, statusCode: 200, json: ["error": "still pending"])
        api.enqueueJSON(path: tenantsPath, statusCode: 200, json: ["message": "still invalid"])
        api.refreshResults = [
            .success(try makeAuthResponse(accessToken: "rotated-access-token", refreshToken: "rotated-refresh-token"))
        ]

        do {
            _ = try await api.me(accessToken: "access-token", refreshToken: "refresh-token")
            XCTFail("Expected tenants payload failure")
        } catch let error as ApiError {
            if case .meEndpointFailed(let statusCode, let path) = error {
                XCTAssertEqual(statusCode, 0)
                XCTAssertEqual(path, tenantsPath)
            } else {
                XCTFail("Expected meEndpointFailed(0), got \(error)")
            }
        } catch {
            XCTFail("Expected ApiError, got \(error)")
        }

        XCTAssertEqual(api.callCounts[mePath], 1)
        XCTAssertEqual(api.callCounts[tenantsPath], 3)
        XCTAssertEqual(api.refreshCallCount, 1)
    }

    func test_me_correctsActiveTenantWhenItIsNotInTenantList() async throws {
        let tenantA = TestDataFactory.makeTenant(id: "tenant-a", name: "Tenant A", tenantId: "tenant-a")
        let tenantB = TestDataFactory.makeTenant(id: "tenant-b", name: "Tenant B", tenantId: "tenant-b")
        let staleActiveTenant = TestDataFactory.makeTenant(id: "tenant-stale", name: "Stale", tenantId: "tenant-stale")

        api.enqueueJSON(path: mePath, statusCode: 200, json: makeUserResponse(tenantId: "tenant-stale"))
        api.enqueueJSON(path: tenantsPath, statusCode: 200, json: [
            "tenants": [tenantA, tenantB],
            "activeTenant": staleActiveTenant
        ])

        let result = try await api.me(accessToken: "access-token", refreshToken: "refresh-token")
        let user = try XCTUnwrap(result.user)

        XCTAssertEqual(user.activeTenant.id, "tenant-a")
        XCTAssertEqual(user.tenantId, "tenant-a")
        XCTAssertEqual(api.callCounts[mePath], 1)
        XCTAssertEqual(api.callCounts[tenantsPath], 1)
        XCTAssertEqual(api.refreshCallCount, 0)
    }

    private func makeUserResponse(email: String = "test@example.com", tenantId: String = "tenant-123") -> [String: Any] {
        let tenant = TestDataFactory.makeTenant(id: tenantId, name: "Tenant \(tenantId)", tenantId: tenantId)
        return TestDataFactory.makeUser(
            email: email,
            tenantId: tenantId,
            tenantIds: [tenantId],
            tenants: [tenant],
            activeTenant: tenant
        )
    }

    private func makeTenantsResponse(tenantId: String = "tenant-123") -> [String: Any] {
        let tenant = TestDataFactory.makeTenant(id: tenantId, name: "Tenant \(tenantId)", tenantId: tenantId)
        return [
            "tenants": [tenant],
            "activeTenant": tenant
        ]
    }

    private func makeAuthResponse(accessToken: String, refreshToken: String) throws -> AuthResponse {
        let json = TestDataFactory.makeAuthResponse(
            refreshToken: refreshToken,
            accessToken: accessToken
        )
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }
}
