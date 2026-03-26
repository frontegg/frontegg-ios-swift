//
//  EntitlementsTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

class MockEntitlementsApi: Api {
    var entitlementsResponse: (Data, HTTPURLResponse)?
    var getRequestCallCount = 0

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
        getRequestCallCount += 1
        if path.contains("user-entitlements"), let response = entitlementsResponse {
            return (response.0, response.1)
        }
        throw ApiError.invalidUrl("unexpected path: \(path)")
    }
}

final class EntitlementsTests: XCTestCase {

    var mockApi: MockEntitlementsApi!
    var entitlements: Entitlements!

    override func setUp() {
        super.setUp()
        mockApi = MockEntitlementsApi()
    }

    override func tearDown() {
        entitlements = nil
        mockApi = nil
        super.tearDown()
    }

    func test_EntitlementState_empty() {
        XCTAssertTrue(EntitlementState.empty.featureKeys.isEmpty)
        XCTAssertTrue(EntitlementState.empty.permissionKeys.isEmpty)
    }

    func test_Entitlement_initAndEquality() {
        let e1 = Entitlement(isEntitled: true, justification: nil)
        XCTAssertTrue(e1.isEntitled)
        XCTAssertNil(e1.justification)

        let e2 = Entitlement(isEntitled: false, justification: "MISSING_FEATURE")
        XCTAssertFalse(e2.isEntitled)
        XCTAssertEqual(e2.justification, "MISSING_FEATURE")

        XCTAssertEqual(e1, Entitlement(isEntitled: true, justification: nil))
        XCTAssertNotEqual(e1, e2)
    }

    func test_EntitledToOptions_cases() {
        let f = EntitledToOptions.featureKey("sso")
        let p = EntitledToOptions.permissionKey("fe.secure.*")
        switch f {
        case .featureKey(let key): XCTAssertEqual(key, "sso")
        case .permissionKey: XCTFail()
        }
        switch p {
        case .permissionKey(let key): XCTAssertEqual(key, "fe.secure.*")
        case .featureKey: XCTFail()
        }
    }

    func test_whenDisabled_checkFeature_returnsNotEntitled() {
        entitlements = Entitlements(.init(api: mockApi, enabled: false))
        let result = entitlements.checkFeature(featureKey: "sso")
        XCTAssertFalse(result.isEntitled)
        XCTAssertEqual(result.justification, "ENTITLEMENTS_DISABLED")
    }

    func test_whenDisabled_checkPermission_returnsNotEntitled() {
        entitlements = Entitlements(.init(api: mockApi, enabled: false))
        let result = entitlements.checkPermission(permissionKey: "fe.secure.*")
        XCTAssertFalse(result.isEntitled)
        XCTAssertEqual(result.justification, "ENTITLEMENTS_DISABLED")
    }

    func test_whenEnabledAndEmptyState_checkFeature_returnsMissingFeature() {
        entitlements = Entitlements(.init(api: mockApi, enabled: true))
        let result = entitlements.checkFeature(featureKey: "sso")
        XCTAssertFalse(result.isEntitled)
        XCTAssertEqual(result.justification, "MISSING_FEATURE")
    }

    func test_whenEnabledAndEmptyState_checkPermission_returnsMissingPermission() {
        entitlements = Entitlements(.init(api: mockApi, enabled: true))
        let result = entitlements.checkPermission(permissionKey: "fe.secure.*")
        XCTAssertFalse(result.isEntitled)
        XCTAssertEqual(result.justification, "MISSING_PERMISSION")
    }

    func test_load_withValidJson_updatesStateAndReturnsTrue() async {
        let json = """
        {"features":{"test-feature":{},"sso":{}},"permissions":{"fe.secure.*":true,"fe.connectivity.*":false}}
        """
        let data = json.data(using: .utf8)!
        let response = HTTPURLResponse(url: URL(string: "https://test.example.com/e")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        mockApi.entitlementsResponse = (data, response)

        entitlements = Entitlements(.init(api: mockApi, enabled: true))
        let success = await entitlements.load(accessToken: "token")
        XCTAssertTrue(success)
        XCTAssertEqual(mockApi.getRequestCallCount, 1)
        XCTAssertTrue(entitlements.state.featureKeys.contains("test-feature"))
        XCTAssertTrue(entitlements.state.featureKeys.contains("sso"))
        XCTAssertTrue(entitlements.state.permissionKeys.contains("fe.secure.*"))
        XCTAssertFalse(entitlements.state.permissionKeys.contains("fe.connectivity.*"))

        let featureResult = entitlements.checkFeature(featureKey: "sso")
        XCTAssertTrue(featureResult.isEntitled)
        XCTAssertNil(featureResult.justification)

        let permResult = entitlements.checkPermission(permissionKey: "fe.secure.*")
        XCTAssertTrue(permResult.isEntitled)

        let missingFeature = entitlements.checkFeature(featureKey: "unknown")
        XCTAssertFalse(missingFeature.isEntitled)
        XCTAssertEqual(missingFeature.justification, "MISSING_FEATURE")
    }

    func test_load_whenDisabled_returnsFalse() async {
        entitlements = Entitlements(.init(api: mockApi, enabled: false))
        let success = await entitlements.load(accessToken: "token")
        XCTAssertFalse(success)
        XCTAssertEqual(mockApi.getRequestCallCount, 0)
    }

    func test_clear_resetsState() async {
        let json = "{\"features\":{\"sso\":{}},\"permissions\":{\"fe.secure.*\":true}}"
        let data = json.data(using: .utf8)!
        let response = HTTPURLResponse(url: URL(string: "https://test.example.com/e")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        mockApi.entitlementsResponse = (data, response)

        entitlements = Entitlements(.init(api: mockApi, enabled: true))
        _ = await entitlements.load(accessToken: "token")
        XCTAssertTrue(entitlements.state.featureKeys.contains("sso"))

        entitlements.clear()
        XCTAssertTrue(entitlements.state.featureKeys.isEmpty)
        XCTAssertTrue(entitlements.state.permissionKeys.isEmpty)
        let result = entitlements.checkFeature(featureKey: "sso")
        XCTAssertFalse(result.isEntitled)
    }
}
