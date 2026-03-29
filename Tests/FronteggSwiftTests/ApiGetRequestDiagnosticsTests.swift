//
//  ApiGetRequestDiagnosticsTests.swift
//  FronteggSwiftTests
//
//  Verifies breadcrumb and Sentry logging behavior for retry-enabled GET requests.
//

import XCTest
@testable import FronteggSwift

private final class DiagnosticsApi: Api {
    enum Outcome {
        case response(statusCode: Int, data: Data)
        case error(Error)
    }

    struct BreadcrumbRecord {
        let method: String
        let url: URL?
        let statusCode: Int?
        let followRedirect: Bool
        let hadError: Bool
    }

    struct ErrorRecord {
        let error: Error
        let method: String
        let path: String
        let followRedirect: Bool
        let statusCode: Int?
    }

    var outcomes: [Outcome] = []
    var requests: [URLRequest] = []
    var breadcrumbs: [BreadcrumbRecord] = []
    var loggedErrors: [ErrorRecord] = []

    init() {
        super.init(baseUrl: "https://test.example.com", clientId: "test-client", applicationId: nil)
    }

    override func performData(
        for request: URLRequest,
        timeout: Int,
        followRedirect: Bool
    ) async throws -> (Data, URLResponse) {
        requests.append(request)

        guard !outcomes.isEmpty else {
            throw ApiError.invalidUrl("No mock outcome configured")
        }

        switch outcomes.removeFirst() {
        case .response(let statusCode, let data):
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://test.example.com/fallback")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (data, response)
        case .error(let error):
            throw error
        }
    }

    override func addHttpBreadcrumb(
        method: String,
        url: URL?,
        statusCode: Int?,
        traceId: String?,
        durationMs: Int?,
        requestBodySize: Int?,
        responseBodySize: Int?,
        followRedirect: Bool,
        error: Error? = nil
    ) {
        breadcrumbs.append(
            BreadcrumbRecord(
                method: method,
                url: url,
                statusCode: statusCode,
                followRedirect: followRedirect,
                hadError: error != nil
            )
        )
    }

    override func logHttpError(
        _ error: Error,
        method: String,
        path: String,
        followRedirect: Bool,
        statusCode: Int? = nil
    ) {
        loggedErrors.append(
            ErrorRecord(
                error: error,
                method: method,
                path: path,
                followRedirect: followRedirect,
                statusCode: statusCode
            )
        )
    }

    override func sleepBeforeRetry(attempt: Int) async {
        // Tests should not pay real retry backoff delays.
    }
}

final class ApiGetRequestDiagnosticsTests: XCTestCase {
    private let mePath = "identity/resources/users/v2/me"

    private func makeApi() -> DiagnosticsApi {
        DiagnosticsApi()
    }

    func test_getRequest_401LogsSingleStatusAwareTerminalErrorWithoutRetry() async {
        let api = makeApi()
        api.outcomes = [
            .response(statusCode: 401, data: Data("{}".utf8))
        ]

        do {
            _ = try await api.getRequest(path: mePath, accessToken: "token", retries: 3)
            XCTFail("Expected 401 terminal failure")
        } catch let error as ApiError {
            if case .meEndpointFailed(let statusCode, let path) = error {
                XCTAssertEqual(statusCode, 401)
                XCTAssertEqual(path, mePath)
            } else {
                XCTFail("Expected meEndpointFailed(401), got \(error)")
            }
        } catch {
            XCTFail("Expected ApiError, got \(error)")
        }

        XCTAssertEqual(api.requests.count, 1)
        XCTAssertEqual(api.breadcrumbs.count, 1)
        XCTAssertEqual(api.breadcrumbs.first?.method, "GET")
        XCTAssertEqual(api.breadcrumbs.first?.statusCode, 401)
        XCTAssertEqual(api.breadcrumbs.first?.followRedirect, true)
        XCTAssertFalse(api.breadcrumbs.first?.hadError ?? true)
        XCTAssertFalse(api.breadcrumbs.contains { $0.statusCode == nil && $0.hadError })

        XCTAssertEqual(api.loggedErrors.count, 1)
        XCTAssertEqual(api.loggedErrors.first?.method, "GET")
        XCTAssertEqual(api.loggedErrors.first?.path, mePath)
        XCTAssertEqual(api.loggedErrors.first?.statusCode, 401)
        XCTAssertEqual(api.loggedErrors.first?.followRedirect, true)
    }

    func test_getRequest_terminalTransientHttpFailureLogsFinalErrorOnce() async {
        let api = makeApi()
        api.outcomes = [
            .response(statusCode: 502, data: Data("{}".utf8)),
            .response(statusCode: 502, data: Data("{}".utf8)),
            .response(statusCode: 502, data: Data("{}".utf8))
        ]

        do {
            _ = try await api.getRequest(path: mePath, accessToken: "token", retries: 2)
            XCTFail("Expected transient HTTP failure")
        } catch let error as ApiError {
            if case .meEndpointFailed(let statusCode, let path) = error {
                XCTAssertEqual(statusCode, 502)
                XCTAssertEqual(path, mePath)
            } else {
                XCTFail("Expected meEndpointFailed(502), got \(error)")
            }
        } catch {
            XCTFail("Expected ApiError, got \(error)")
        }

        XCTAssertEqual(api.requests.count, 3)
        XCTAssertEqual(api.breadcrumbs.count, 3)
        XCTAssertEqual(api.breadcrumbs.map(\.statusCode), [502, 502, 502])
        XCTAssertTrue(api.breadcrumbs.allSatisfy { !$0.hadError })

        XCTAssertEqual(api.loggedErrors.count, 1)
        XCTAssertEqual(api.loggedErrors.first?.method, "GET")
        XCTAssertEqual(api.loggedErrors.first?.path, mePath)
        XCTAssertEqual(api.loggedErrors.first?.statusCode, 502)
    }

    func test_getRequest_transientHttpRetryThenSuccessDoesNotLogTerminalError() async throws {
        let api = makeApi()
        api.outcomes = [
            .response(statusCode: 502, data: Data("{}".utf8)),
            .response(statusCode: 200, data: Data("{}".utf8))
        ]

        let (_, response) = try await api.getRequest(path: mePath, accessToken: "token", retries: 1)

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(api.requests.count, 2)
        XCTAssertEqual(api.breadcrumbs.map(\.statusCode), [502, 200])
        XCTAssertTrue(api.breadcrumbs.allSatisfy { !$0.hadError })
        XCTAssertTrue(api.loggedErrors.isEmpty)
    }

    func test_getRequest_transportErrorsKeepCatchPathLoggingBehavior() async {
        let api = makeApi()
        let timeoutError = URLError(.timedOut)
        api.outcomes = [
            .error(timeoutError),
            .error(timeoutError)
        ]

        do {
            _ = try await api.getRequest(path: mePath, accessToken: "token", retries: 1)
            XCTFail("Expected transport error")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        } catch {
            XCTFail("Expected URLError, got \(error)")
        }

        XCTAssertEqual(api.requests.count, 2)
        XCTAssertEqual(api.breadcrumbs.count, 2)
        XCTAssertTrue(api.breadcrumbs.allSatisfy { $0.statusCode == nil && $0.hadError })
        XCTAssertEqual(api.loggedErrors.count, 2)
        XCTAssertTrue(api.loggedErrors.allSatisfy { $0.statusCode == nil })
    }

    func test_getRequest_nonTransientHttpResponseStillReturnsWithoutTerminalErrorLogging() async throws {
        let api = makeApi()
        api.outcomes = [
            .response(statusCode: 403, data: Data("blocked".utf8))
        ]

        let (data, response) = try await api.getRequest(path: mePath, accessToken: "token", retries: 3)

        XCTAssertEqual(String(decoding: data, as: UTF8.self), "blocked")
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 403)
        XCTAssertEqual(api.requests.count, 1)
        XCTAssertEqual(api.breadcrumbs.count, 1)
        XCTAssertEqual(api.breadcrumbs.first?.statusCode, 403)
        XCTAssertFalse(api.breadcrumbs.first?.hadError ?? true)
        XCTAssertTrue(api.loggedErrors.isEmpty)
    }
}
