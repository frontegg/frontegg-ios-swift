//
//  AdminPortalWebViewTests.swift
//  FronteggSwiftTests
//

import XCTest
import WebKit
@testable import FronteggSwift

@available(iOS 14.0, *)
final class AdminPortalWebViewTests: XCTestCase {

    // MARK: - portalURL(baseUrl:applicationId:)

    func test_portalURL_appendsAppIdQueryParam_whenApplicationIdPresent() {
        let url = AdminPortalWebView.portalURL(
            baseUrl: "https://app-x4gr8g28fxr5.frontegg.com",
            applicationId: "910a4f81-788a-4184-8ad0-acf355afc66f"
        )

        XCTAssertEqual(
            url?.absoluteString,
            "https://app-x4gr8g28fxr5.frontegg.com/oauth/portal?appId=910a4f81-788a-4184-8ad0-acf355afc66f"
        )
    }

    func test_portalURL_omitsAppIdQueryParam_whenApplicationIdNil() {
        let url = AdminPortalWebView.portalURL(
            baseUrl: "https://app-x4gr8g28fxr5.frontegg.com",
            applicationId: nil
        )

        XCTAssertEqual(
            url?.absoluteString,
            "https://app-x4gr8g28fxr5.frontegg.com/oauth/portal"
        )
    }

    func test_portalURL_omitsAppIdQueryParam_whenApplicationIdEmpty() {
        let url = AdminPortalWebView.portalURL(
            baseUrl: "https://app-x4gr8g28fxr5.frontegg.com",
            applicationId: ""
        )

        XCTAssertEqual(
            url?.absoluteString,
            "https://app-x4gr8g28fxr5.frontegg.com/oauth/portal"
        )
    }

    func test_portalURL_preservesBaseUrlPath_whenBaseUrlHasSubpath() {
        // Vanity-domain configurations sometimes route Frontegg under a path
        // prefix; the portal URL must inherit that prefix.
        let url = AdminPortalWebView.portalURL(
            baseUrl: "https://acme.com/auth",
            applicationId: nil
        )

        XCTAssertEqual(url?.absoluteString, "https://acme.com/auth/oauth/portal")
    }

    func test_portalURL_percentEncodesApplicationId_whenContainsReservedChars() {
        // Defensive — applicationIds are GUIDs in practice, but URLComponents
        // should still produce a valid URL if a configuration is exotic.
        let url = AdminPortalWebView.portalURL(
            baseUrl: "https://app.frontegg.com",
            applicationId: "id with spaces"
        )

        XCTAssertNotNil(url)
        XCTAssertEqual(
            url?.query,
            "appId=id%20with%20spaces"
        )
    }

    // MARK: - Coordinator.webViewDidClose

    @MainActor
    func test_coordinator_invokesOnClose_whenWebViewDidCloseFires() {
        let expectation = expectation(description: "onClose invoked")
        let coordinator = AdminPortalWebView.Coordinator(onClose: {
            expectation.fulfill()
        })

        coordinator.webViewDidClose(WKWebView())

        wait(for: [expectation], timeout: 1.0)
    }

    @MainActor
    func test_coordinator_doesNotCrash_whenOnCloseIsNilAndWebViewDidCloseFires() {
        let coordinator = AdminPortalWebView.Coordinator(onClose: nil)

        // Should be a no-op; if the optional-call wasn't safe this would crash.
        coordinator.webViewDidClose(WKWebView())
    }

    // MARK: - Coordinator navigation policy

    @MainActor
    func test_coordinator_allowsAllNavigation_byDefault() {
        let coordinator = AdminPortalWebView.Coordinator(onClose: nil)
        let request = URLRequest(url: URL(string: "https://app.frontegg.com/oauth/portal")!)
        let action = StubNavigationAction(request: request)

        var receivedPolicy: WKNavigationActionPolicy?
        coordinator.webView(WKWebView(), decidePolicyFor: action) { policy in
            receivedPolicy = policy
        }

        XCTAssertEqual(receivedPolicy, .allow)
    }

}

// MARK: - Stubs

/// `WKNavigationAction` cannot be instantiated directly in tests; subclass to
/// inject a synthetic request.
private final class StubNavigationAction: WKNavigationAction {
    private let stubRequest: URLRequest

    init(request: URLRequest) {
        self.stubRequest = request
        super.init()
    }

    override var request: URLRequest { stubRequest }
}
