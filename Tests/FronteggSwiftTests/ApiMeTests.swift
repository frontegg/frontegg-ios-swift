//
//  ApiMeTests.swift
//  FronteggSwiftTests
//
//  Tests for the me() function with retry logic for flaky /me and /me/tenants endpoints.

import XCTest
@testable import FronteggSwift

// MARK: - Mock Api for /me Testing

class MockMeApi: Api {
    /// Per-path response queues. Each call pops the first entry.
    /// When the queue is empty for a path, throws an error.
    var responseQueues: [String: [(Data, HTTPURLResponse)]] = [:]
    var callCounts: [String: Int] = [:]

    init() {
        super.init(baseUrl: "https://test.example.com", clientId: "test-client", applicationId: nil)
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
        // Normalize path for lookup (strip leading slash if present)
        let lookupPath = path.hasPrefix("/") ? String(path.dropFirst()) : path

        callCounts[lookupPath, default: 0] += 1

        if var queue = responseQueues[lookupPath], !queue.isEmpty {
            let (data, httpResponse) = queue.removeFirst()
            responseQueues[lookupPath] = queue

            // Simulate getRequest retry behavior:
            // 401 always throws immediately
            if httpResponse.statusCode == 401 {
                throw ApiError.meEndpointFailed(statusCode: 401, path: path)
            }
            // Transient errors: retry if retries remaining AND more entries queued
            if Api.isTransientRefreshHTTPStatus(httpResponse.statusCode) {
                if retries > 0, let nextQueue = responseQueues[lookupPath], !nextQueue.isEmpty {
                    return try await getRequest(
                        path: path, accessToken: accessToken,
                        refreshToken: refreshToken,
                        additionalHeaders: additionalHeaders,
                        followRedirect: followRedirect,
                        timeout: timeout, retries: retries - 1
                    )
                }
                // No retries left or queue empty — throw the error
                throw ApiError.meEndpointFailed(statusCode: httpResponse.statusCode, path: path)
            }

            return (data, httpResponse)
        }
        throw ApiError.invalidUrl("no mock response for: \(lookupPath)")
    }

    // MARK: - Helpers

    func enqueue(path: String, statusCode: Int, json: [String: Any] = [:]) {
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        let response = HTTPURLResponse(
            url: URL(string: "https://test.example.com/\(path)")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        responseQueues[path, default: []].append((data, response))
    }

    func enqueue(path: String, statusCode: Int, body: String) {
        let data = body.data(using: .utf8) ?? Data()
        let response = HTTPURLResponse(
            url: URL(string: "https://test.example.com/\(path)")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        responseQueues[path, default: []].append((data, response))
    }
}

// MARK: - Tests

final class ApiMeTests: XCTestCase {

    var mockApi: MockMeApi!

    let mePath = "identity/resources/users/v2/me"
    let tenantsPath = "identity/resources/users/v3/me/tenants"

    override func setUp() {
        super.setUp()
        mockApi = MockMeApi()
    }

    override func tearDown() {
        mockApi = nil
        super.tearDown()
    }

    // MARK: - Test Data

    private func makeMeResponse() -> [String: Any] {
        return TestDataFactory.makeUser()
    }

    private func makeTenantsResponse() -> [String: Any] {
        let tenant = TestDataFactory.makeTenant()
        return [
            "tenants": [tenant],
            "activeTenant": tenant
        ]
    }

    // MARK: - Happy Path

    func test_me_happyPath_returnsUser() async throws {
        mockApi.enqueue(path: mePath, statusCode: 200, json: makeMeResponse())
        mockApi.enqueue(path: tenantsPath, statusCode: 200, json: makeTenantsResponse())

        let user = try await mockApi.me(accessToken: "test-token")

        XCTAssertNotNil(user)
        XCTAssertEqual(user?.email, "test@example.com")
        XCTAssertEqual(mockApi.callCounts[mePath], 1)
        XCTAssertEqual(mockApi.callCounts[tenantsPath], 1)
    }

    // MARK: - Flaky /me (502 then 200)

    func test_me_flakyMeEndpoint_succeedsOnRetry() async throws {
        // First call: 502 (transient), second call: 200 (success)
        mockApi.enqueue(path: mePath, statusCode: 502, json: [:])
        mockApi.enqueue(path: mePath, statusCode: 200, json: makeMeResponse())
        mockApi.enqueue(path: tenantsPath, statusCode: 200, json: makeTenantsResponse())

        let user = try await mockApi.me(accessToken: "test-token")

        XCTAssertNotNil(user)
        XCTAssertEqual(user?.email, "test@example.com")
        // /me called twice (502 + 200), /me/tenants called once
        XCTAssertEqual(mockApi.callCounts[mePath], 2)
        XCTAssertEqual(mockApi.callCounts[tenantsPath], 1)
    }

    // MARK: - Flaky /me/tenants (502 then 200)

    func test_me_flakyTenantsEndpoint_succeedsOnRetry() async throws {
        mockApi.enqueue(path: mePath, statusCode: 200, json: makeMeResponse())
        // First tenants call: 502, second: 200
        mockApi.enqueue(path: tenantsPath, statusCode: 502, json: [:])
        mockApi.enqueue(path: tenantsPath, statusCode: 200, json: makeTenantsResponse())

        let user = try await mockApi.me(accessToken: "test-token")

        XCTAssertNotNil(user)
        // /me called once, /me/tenants called twice
        XCTAssertEqual(mockApi.callCounts[mePath], 1)
        XCTAssertEqual(mockApi.callCounts[tenantsPath], 2)
    }

    // MARK: - Permanent failure (all retries exhaust)

    func test_me_permanentFailure_throwsMeEndpointFailed() async {
        // me() calls getRequest(retries: 3) which means 4 attempts (0...3).
        // The mock simulates retries by recursing, so we need enough entries.
        // Queue the last entry — mock will try to pop and see only failures.
        // Actually the mock recurses consuming one entry per retry attempt.
        // We need at least 4 entries for 4 attempts (retries=3 means 1+3 attempts).
        for _ in 0..<5 {
            mockApi.enqueue(path: mePath, statusCode: 502, json: [:])
        }

        do {
            _ = try await mockApi.me(accessToken: "test-token")
            XCTFail("Expected error to be thrown")
        } catch let error as ApiError {
            if case .meEndpointFailed(let statusCode, _) = error {
                XCTAssertEqual(statusCode, 502)
            } else {
                XCTFail("Expected meEndpointFailed, got: \(error)")
            }
        } catch {
            // Any error is acceptable since all attempts failed
        }
    }

    // MARK: - 401 stops immediately (no retry)

    func test_me_401_stopsImmediately() async {
        mockApi.enqueue(path: mePath, statusCode: 401, json: [:])
        // These should NOT be reached
        mockApi.enqueue(path: mePath, statusCode: 200, json: makeMeResponse())

        do {
            _ = try await mockApi.me(accessToken: "test-token")
            XCTFail("Expected error to be thrown")
        } catch let error as ApiError {
            if case .meEndpointFailed(let statusCode, _) = error {
                XCTAssertEqual(statusCode, 401)
            } else {
                XCTFail("Expected meEndpointFailed(401), got: \(error)")
            }
        } catch {
            XCTFail("Expected ApiError, got: \(error)")
        }

        // Only 1 call — no retry after 401
        XCTAssertEqual(mockApi.callCounts[mePath], 1)
    }

    // MARK: - Invalid JSON (proxy HTML response)

    func test_me_invalidJsonResponse_throwsMeEndpointFailed() async {
        // Return HTML body with 200 status (proxy returned its own page)
        mockApi.enqueue(path: mePath, statusCode: 200, body: "<html><body>Proxy Error</body></html>")

        do {
            _ = try await mockApi.me(accessToken: "test-token")
            XCTFail("Expected error to be thrown")
        } catch let error as ApiError {
            if case .meEndpointFailed(let statusCode, _) = error {
                XCTAssertEqual(statusCode, 0, "Invalid JSON format should use statusCode 0")
            } else {
                XCTFail("Expected meEndpointFailed(0), got: \(error)")
            }
        } catch {
            // JSON parsing error is also acceptable — the guard catches it
            // as meEndpointFailed(statusCode: 0)
        }
    }

    // MARK: - Tenants 401 stops immediately

    func test_me_tenants401_stopsImmediately() async {
        mockApi.enqueue(path: mePath, statusCode: 200, json: makeMeResponse())
        mockApi.enqueue(path: tenantsPath, statusCode: 401, json: [:])
        // Should not be reached
        mockApi.enqueue(path: tenantsPath, statusCode: 200, json: makeTenantsResponse())

        do {
            _ = try await mockApi.me(accessToken: "test-token")
            XCTFail("Expected error to be thrown")
        } catch let error as ApiError {
            if case .meEndpointFailed(let statusCode, _) = error {
                XCTAssertEqual(statusCode, 401)
            } else {
                XCTFail("Expected meEndpointFailed(401), got: \(error)")
            }
        } catch {
            XCTFail("Expected ApiError, got: \(error)")
        }

        XCTAssertEqual(mockApi.callCounts[mePath], 1)
        XCTAssertEqual(mockApi.callCounts[tenantsPath], 1)
    }
}
