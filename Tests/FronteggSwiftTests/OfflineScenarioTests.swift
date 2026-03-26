//
//  OfflineScenarioTests.swift
//  FronteggSwiftTests
//
//  Comprehensive offline scenario matrix tests covering the full refresh→me→tenant flow.
//  Tests the Api layer behavior for each error type and status code combination.

import XCTest
@testable import FronteggSwift

// MARK: - Mock Api for Offline Scenarios

/// Controls each endpoint's behavior independently with sequential response queues.
class MockOfflineApi: Api {

    /// Per-path response queues. Each getRequest call pops the first entry.
    var responseQueues: [String: [(statusCode: Int, data: Data, error: Error?)]] = [:]
    var callLog: [(path: String, attempt: Int)] = []
    private var callCounts: [String: Int] = [:]

    init() {
        super.init(baseUrl: "https://test.frontegg.com", clientId: "test-client-id", applicationId: nil)
    }

    /// Enqueue an HTTP response for a specific path.
    func enqueueResponse(path: String, statusCode: Int, json: [String: Any] = [:]) {
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        responseQueues[path, default: []].append((statusCode: statusCode, data: data, error: nil))
    }

    /// Enqueue a raw string response (e.g., HTML from proxy).
    func enqueueResponse(path: String, statusCode: Int, body: String) {
        let data = body.data(using: .utf8) ?? Data()
        responseQueues[path, default: []].append((statusCode: statusCode, data: data, error: nil))
    }

    /// Enqueue a network error (e.g., URLError.timedOut).
    func enqueueError(path: String, error: Error) {
        responseQueues[path, default: []].append((statusCode: 0, data: Data(), error: error))
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
        callLog.append((path: normalizedPath, attempt: callCounts[normalizedPath]!))

        if var queue = responseQueues[normalizedPath], !queue.isEmpty {
            let entry = queue.removeFirst()
            responseQueues[normalizedPath] = queue

            // If there's an error to throw
            if let error = entry.error {
                if retries > 0, let nextQueue = responseQueues[normalizedPath], !nextQueue.isEmpty {
                    return try await getRequest(
                        path: path, accessToken: accessToken, refreshToken: refreshToken,
                        additionalHeaders: additionalHeaders, followRedirect: followRedirect,
                        timeout: timeout, retries: retries - 1
                    )
                }
                throw error
            }

            let url = URL(string: "https://test.frontegg.com/\(normalizedPath)")!
            let httpResponse = HTTPURLResponse(url: url, statusCode: entry.statusCode, httpVersion: nil, headerFields: nil)!

            // 401 always throws immediately
            if entry.statusCode == 401 {
                throw ApiError.meEndpointFailed(statusCode: 401, path: path)
            }

            // Transient errors: retry if possible
            if Api.isTransientRefreshHTTPStatus(entry.statusCode) {
                if retries > 0, let nextQueue = responseQueues[normalizedPath], !nextQueue.isEmpty {
                    return try await getRequest(
                        path: path, accessToken: accessToken, refreshToken: refreshToken,
                        additionalHeaders: additionalHeaders, followRedirect: followRedirect,
                        timeout: timeout, retries: retries - 1
                    )
                }
                throw ApiError.meEndpointFailed(statusCode: entry.statusCode, path: path)
            }

            return (entry.data, httpResponse)
        }

        throw ApiError.invalidUrl("No mock response for path: \(normalizedPath)")
    }

    func callCount(for path: String) -> Int {
        return callCounts[path] ?? 0
    }
}

// MARK: - Test Data Helpers

private let mePath = "identity/resources/users/v2/me"
private let tenantsPath = "identity/resources/users/v3/me/tenants"

private func validMeResponse() -> [String: Any] {
    return TestDataFactory.makeUser()
}

private func validTenantsResponse() -> [String: Any] {
    let tenant = TestDataFactory.makeTenant()
    return ["tenants": [tenant], "activeTenant": tenant]
}

// MARK: - Scenario M: /me Phase Tests

final class OfflineScenario_MePhaseTests: XCTestCase {

    var api: MockOfflineApi!

    override func setUp() {
        super.setUp()
        api = MockOfflineApi()
    }

    // MARK: M1 — Happy path

    func test_M1_meAndTenants200_returnsFullUser() async throws {
        api.enqueueResponse(path: mePath, statusCode: 200, json: validMeResponse())
        api.enqueueResponse(path: tenantsPath, statusCode: 200, json: validTenantsResponse())

        let user = try await api.me(accessToken: "test-token")
        XCTAssertNotNil(user)
        XCTAssertEqual(user?.email, "test@example.com")
        XCTAssertEqual(api.callCount(for: mePath), 1)
        XCTAssertEqual(api.callCount(for: tenantsPath), 1)
    }

    // MARK: M2 — /me 502, all retries fail

    func test_M2_me502_allRetriesFail_throwsMeEndpointFailed() async {
        // me() calls getRequest(retries:3) → 4 attempts total
        for _ in 0..<4 { api.enqueueResponse(path: mePath, statusCode: 502) }

        do {
            _ = try await api.me(accessToken: "test-token")
            XCTFail("Expected error")
        } catch let error as ApiError {
            if case .meEndpointFailed(let code, _) = error {
                XCTAssertEqual(code, 502)
            } else { XCTFail("Wrong ApiError: \(error)") }
        } catch {
            // Network-level error also acceptable
        }
    }

    // MARK: M3 — /me 500, all retries fail

    func test_M3_me500_allRetriesFail_throwsMeEndpointFailed() async {
        for _ in 0..<4 { api.enqueueResponse(path: mePath, statusCode: 500) }

        do {
            _ = try await api.me(accessToken: "test-token")
            XCTFail("Expected error")
        } catch let error as ApiError {
            if case .meEndpointFailed(let code, _) = error { XCTAssertEqual(code, 500) }
            else { XCTFail("Wrong ApiError: \(error)") }
        } catch {}
    }

    // MARK: M4 — /me 408 timeout

    func test_M4_me408_allRetriesFail_throwsMeEndpointFailed() async {
        for _ in 0..<4 { api.enqueueResponse(path: mePath, statusCode: 408) }

        do {
            _ = try await api.me(accessToken: "test-token")
            XCTFail("Expected error")
        } catch let error as ApiError {
            if case .meEndpointFailed(let code, _) = error { XCTAssertEqual(code, 408) }
            else { XCTFail("Wrong ApiError: \(error)") }
        } catch {}
    }

    // MARK: M5 — /me 429 rate limit

    func test_M5_me429_allRetriesFail_throwsMeEndpointFailed() async {
        for _ in 0..<4 { api.enqueueResponse(path: mePath, statusCode: 429) }

        do {
            _ = try await api.me(accessToken: "test-token")
            XCTFail("Expected error")
        } catch let error as ApiError {
            if case .meEndpointFailed(let code, _) = error { XCTAssertEqual(code, 429) }
            else { XCTFail("Wrong ApiError: \(error)") }
        } catch {}
    }

    // MARK: M6 — /me 401, no retry

    func test_M6_me401_stopsImmediately_noRetry() async {
        api.enqueueResponse(path: mePath, statusCode: 401)
        // This should NOT be reached
        api.enqueueResponse(path: mePath, statusCode: 200, json: validMeResponse())

        do {
            _ = try await api.me(accessToken: "test-token")
            XCTFail("Expected error")
        } catch let error as ApiError {
            if case .meEndpointFailed(let code, _) = error { XCTAssertEqual(code, 401) }
            else { XCTFail("Wrong ApiError: \(error)") }
        } catch {}

        XCTAssertEqual(api.callCount(for: mePath), 1, "401 should not trigger retry")
    }

    // MARK: M7 — /me 403 (proxy blocked)

    func test_M7_me403_notTransient_noRetry() async {
        api.enqueueResponse(path: mePath, statusCode: 403)

        do {
            _ = try await api.me(accessToken: "test-token")
            // 403 is not transient, not 401 → returned as-is (status not checked without retries)
            // Actually with retries:3, 403 is not in isTransientRefreshHTTPStatus → returned as data
            // Then JSON parsing will fail (empty json) → meEndpointFailed(0) from guard
        } catch {}

        // 403 is not retried (not in isTransientRefreshHTTPStatus)
        XCTAssertEqual(api.callCount(for: mePath), 1)
    }

    // MARK: M8 — /me 200 with HTML body (proxy page)

    func test_M8_me200_htmlBody_throwsMeEndpointFailed0() async {
        api.enqueueResponse(path: mePath, statusCode: 200, body: "<html><body>Proxy Error</body></html>")

        do {
            _ = try await api.me(accessToken: "test-token")
            XCTFail("Expected error from HTML parsing")
        } catch let error as ApiError {
            if case .meEndpointFailed(let code, _) = error {
                XCTAssertEqual(code, 0, "Invalid JSON should throw with statusCode 0")
            } else { XCTFail("Wrong ApiError: \(error)") }
        } catch {
            // JSONSerialization error is also acceptable
        }
    }

    // MARK: M9 — /me throws URLError.timedOut

    func test_M9_meTimedOut_retriesAndFails() async {
        for _ in 0..<4 {
            api.enqueueError(path: mePath, error: URLError(.timedOut))
        }

        do {
            _ = try await api.me(accessToken: "test-token")
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is URLError || error is ApiError, "Expected URLError or ApiError, got \(type(of: error))")
        }
    }

    // MARK: M10 — /me throws URLError.notConnectedToInternet

    func test_M10_meNotConnected_retriesAndFails() async {
        for _ in 0..<4 {
            api.enqueueError(path: mePath, error: URLError(.notConnectedToInternet))
        }

        do {
            _ = try await api.me(accessToken: "test-token")
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is URLError || error is ApiError)
        }
    }

    // MARK: M11 — /me throws URLError.networkConnectionLost

    func test_M11_meConnectionLost_retriesAndFails() async {
        for _ in 0..<4 {
            api.enqueueError(path: mePath, error: URLError(.networkConnectionLost))
        }

        do {
            _ = try await api.me(accessToken: "test-token")
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is URLError || error is ApiError)
        }
    }

    // MARK: M — Retry recovery: 502 then 200

    func test_M_502ThenSuccess_recoversOnRetry() async throws {
        api.enqueueResponse(path: mePath, statusCode: 502)
        api.enqueueResponse(path: mePath, statusCode: 200, json: validMeResponse())
        api.enqueueResponse(path: tenantsPath, statusCode: 200, json: validTenantsResponse())

        let user = try await api.me(accessToken: "test-token")
        XCTAssertNotNil(user)
        XCTAssertEqual(api.callCount(for: mePath), 2, "/me called twice (502 + 200)")
        XCTAssertEqual(api.callCount(for: tenantsPath), 1)
    }

    // MARK: M — Mixed errors: 502 then timeout then 200

    func test_M_502ThenTimeoutThen200_recovers() async throws {
        api.enqueueResponse(path: mePath, statusCode: 502)
        api.enqueueError(path: mePath, error: URLError(.timedOut))
        api.enqueueResponse(path: mePath, statusCode: 200, json: validMeResponse())
        api.enqueueResponse(path: tenantsPath, statusCode: 200, json: validTenantsResponse())

        let user = try await api.me(accessToken: "test-token")
        XCTAssertNotNil(user)
        XCTAssertEqual(api.callCount(for: mePath), 3)
    }
}

// MARK: - Scenario T: /me/tenants Phase Tests

final class OfflineScenario_TenantsPhaseTests: XCTestCase {

    var api: MockOfflineApi!

    override func setUp() {
        super.setUp()
        api = MockOfflineApi()
        // /me always succeeds in these tests
        api.enqueueResponse(path: mePath, statusCode: 200, json: validMeResponse())
    }

    // MARK: T1 — Happy path

    func test_T1_tenants200_returnsFullUser() async throws {
        api.enqueueResponse(path: tenantsPath, statusCode: 200, json: validTenantsResponse())

        let user = try await api.me(accessToken: "test-token")
        XCTAssertNotNil(user)
    }

    // MARK: T2 — /me/tenants 502, all retries fail

    func test_T2_tenants502_allRetriesFail() async {
        for _ in 0..<4 { api.enqueueResponse(path: tenantsPath, statusCode: 502) }

        do {
            _ = try await api.me(accessToken: "test-token")
            XCTFail("Expected error")
        } catch let error as ApiError {
            if case .meEndpointFailed(let code, _) = error { XCTAssertEqual(code, 502) }
            else { XCTFail("Wrong error: \(error)") }
        } catch {}

        XCTAssertEqual(api.callCount(for: mePath), 1, "/me only called once (succeeded)")
    }

    // MARK: T3 — /me/tenants 401, no retry

    func test_T3_tenants401_stopsImmediately() async {
        api.enqueueResponse(path: tenantsPath, statusCode: 401)
        api.enqueueResponse(path: tenantsPath, statusCode: 200, json: validTenantsResponse())

        do {
            _ = try await api.me(accessToken: "test-token")
            XCTFail("Expected error")
        } catch let error as ApiError {
            if case .meEndpointFailed(let code, _) = error { XCTAssertEqual(code, 401) }
            else { XCTFail("Wrong error: \(error)") }
        } catch {}

        XCTAssertEqual(api.callCount(for: tenantsPath), 1)
    }

    // MARK: T4 — /me/tenants 200 with HTML body

    func test_T4_tenantsHtml_throwsMeEndpointFailed0() async {
        api.enqueueResponse(path: tenantsPath, statusCode: 200, body: "<html>Proxy</html>")

        do {
            _ = try await api.me(accessToken: "test-token")
            XCTFail("Expected error")
        } catch let error as ApiError {
            if case .meEndpointFailed(let code, _) = error { XCTAssertEqual(code, 0) }
            else { XCTFail("Wrong error: \(error)") }
        } catch {}
    }

    // MARK: T5 — /me/tenants timeout

    func test_T5_tenantsTimeout_retriesAndFails() async {
        for _ in 0..<4 { api.enqueueError(path: tenantsPath, error: URLError(.timedOut)) }

        do {
            _ = try await api.me(accessToken: "test-token")
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is URLError || error is ApiError)
        }

        XCTAssertEqual(api.callCount(for: mePath), 1, "/me succeeded, only tenants retried")
    }

    // MARK: T — Recovery: 502 then 200

    func test_T_502ThenSuccess_recoversOnRetry() async throws {
        api.enqueueResponse(path: tenantsPath, statusCode: 502)
        api.enqueueResponse(path: tenantsPath, statusCode: 200, json: validTenantsResponse())

        let user = try await api.me(accessToken: "test-token")
        XCTAssertNotNil(user)
        XCTAssertEqual(api.callCount(for: mePath), 1)
        XCTAssertEqual(api.callCount(for: tenantsPath), 2)
    }
}
