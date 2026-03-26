//
//  FronteggAuthEntitlementsTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

private final class BlockingAuthEntitlementsApi: Api {
    private let stateLock = NSLock()
    private var queuedResponses: [(Data, HTTPURLResponse)] = []
    private var blockedRequestIndexes = Set<Int>()
    private var blockedContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var getRequestCallCount = 0

    var onRequestStarted: ((Int) -> Void)?

    init() {
        super.init(baseUrl: "https://test.example.com", clientId: "test-client-id", applicationId: nil)
    }

    private func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    func enqueueResponse(_ response: (Data, HTTPURLResponse)) {
        withStateLock {
            queuedResponses.append(response)
        }
    }

    func blockRequest(_ index: Int) {
        withStateLock {
            _ = blockedRequestIndexes.insert(index)
        }
    }

    func resumeRequest(_ index: Int) {
        let continuation = withStateLock {
            blockedContinuations.removeValue(forKey: index)
        }
        continuation?.resume()
    }

    func currentCallCount() -> Int {
        withStateLock { getRequestCallCount }
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
        let callIndex: Int
        let shouldBlock: Bool
        let requestStarted: ((Int) -> Void)?

        (callIndex, shouldBlock, requestStarted) = withStateLock {
            getRequestCallCount += 1
            return (
                getRequestCallCount,
                blockedRequestIndexes.contains(getRequestCallCount),
                onRequestStarted
            )
        }

        if shouldBlock {
            await withCheckedContinuation { continuation in
                withStateLock {
                    blockedContinuations[callIndex] = continuation
                }
                requestStarted?(callIndex)
            }
        } else {
            requestStarted?(callIndex)
        }

        let response = withStateLock {
            queuedResponses.removeFirst()
        }
        return (response.0, response.1)
    }
}

final class FronteggAuthEntitlementsTests: XCTestCase {

    private var auth: FronteggAuth!
    private var api: BlockingAuthEntitlementsApi!
    private var credentialManager: CredentialManager!
    private var serviceKey: String!

    override func setUp() {
        super.setUp()
        serviceKey = "frontegg-auth-entitlements-\(UUID().uuidString)"
        credentialManager = CredentialManager(serviceKey: serviceKey)
        auth = FronteggAuth(
            baseUrl: "https://test.example.com",
            clientId: "test-client-id",
            applicationId: nil,
            credentialManager: credentialManager,
            isRegional: false,
            regionData: [],
            embeddedMode: false,
            isLateInit: true,
            entitlementsEnabled: false
        )
        api = BlockingAuthEntitlementsApi()
        auth.api = api
        auth.entitlements = Entitlements(.init(api: api, enabled: true))
        auth.setAccessToken("test-access-token")
        auth.setIsLoading(false)
        auth.setInitializing(false)
        auth.setShowLoader(false)
    }

    override func tearDown() {
        auth.cancelScheduledTokenRefresh()
        credentialManager.clear()
        api.onRequestStarted = nil
        api = nil
        auth = nil
        credentialManager = nil
        serviceKey = nil
        super.tearDown()
    }

    func test_loadEntitlements_coalescesConcurrentCallersIntoSingleRequest() async throws {
        api.enqueueResponse(makeEntitlementsResponse(featureKeys: ["alpha"]))
        api.blockRequest(1)

        let firstRequestStarted = expectation(description: "first request started")
        let firstCompletion = expectation(description: "first completion")
        let secondCompletion = expectation(description: "second completion")

        api.onRequestStarted = { index in
            if index == 1 {
                firstRequestStarted.fulfill()
            }
        }

        var completionResults: [Bool] = []
        auth.loadEntitlements { success in
            XCTAssertTrue(Thread.isMainThread)
            completionResults.append(success)
            firstCompletion.fulfill()
        }

        await fulfillment(of: [firstRequestStarted], timeout: 1.0)

        auth.loadEntitlements { success in
            XCTAssertTrue(Thread.isMainThread)
            completionResults.append(success)
            secondCompletion.fulfill()
        }

        XCTAssertEqual(api.currentCallCount(), 1)

        api.resumeRequest(1)

        await fulfillment(of: [firstCompletion, secondCompletion], timeout: 1.0)

        XCTAssertEqual(api.currentCallCount(), 1)
        XCTAssertEqual(completionResults, [true, true])
        XCTAssertEqual(auth.entitlements.state.featureKeys, Set(["alpha"]))
    }

    func test_loadEntitlements_forceRefreshQueuesSecondPassUntilFirstCompletes() async throws {
        api.enqueueResponse(makeEntitlementsResponse(featureKeys: ["alpha"]))
        api.enqueueResponse(makeEntitlementsResponse(featureKeys: ["beta"]))
        api.blockRequest(1)
        api.blockRequest(2)

        let firstRequestStarted = expectation(description: "first request started")
        let secondRequestStarted = expectation(description: "second request started")
        let firstCompletion = expectation(description: "first completion")
        let secondCompletion = expectation(description: "second completion")

        api.onRequestStarted = { index in
            if index == 1 {
                firstRequestStarted.fulfill()
            } else if index == 2 {
                secondRequestStarted.fulfill()
            }
        }

        var completionResults: [Bool] = []
        auth.loadEntitlements { success in
            XCTAssertTrue(Thread.isMainThread)
            completionResults.append(success)
            firstCompletion.fulfill()
        }

        await fulfillment(of: [firstRequestStarted], timeout: 1.0)

        auth.loadEntitlements(forceRefresh: true) { success in
            XCTAssertTrue(Thread.isMainThread)
            completionResults.append(success)
            secondCompletion.fulfill()
        }

        XCTAssertEqual(api.currentCallCount(), 1)

        api.resumeRequest(1)

        await fulfillment(of: [secondRequestStarted], timeout: 1.0)

        XCTAssertTrue(completionResults.isEmpty)
        XCTAssertEqual(api.currentCallCount(), 2)

        api.resumeRequest(2)

        await fulfillment(of: [firstCompletion, secondCompletion], timeout: 1.0)

        XCTAssertEqual(completionResults, [true, true])
        XCTAssertEqual(auth.entitlements.state.featureKeys, Set(["beta"]))
    }

    private func makeEntitlementsResponse(featureKeys: [String]) -> (Data, HTTPURLResponse) {
        let features = Dictionary(uniqueKeysWithValues: featureKeys.map { ($0, [String: String]()) })
        let json: [String: Any] = [
            "features": features,
            "permissions": [String: Bool]()
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let response = HTTPURLResponse(
            url: URL(string: "https://test.example.com/frontegg/entitlements/api/v2/user-entitlements")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}
