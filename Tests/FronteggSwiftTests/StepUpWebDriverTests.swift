//
//  StepUpWebDriverTests.swift
//  FronteggSwiftTests
//

import XCTest
import WebKit
@testable import FronteggSwift

@MainActor
final class StepUpWebDriverTests: XCTestCase {

    private let authorizeUrl = URL(string: "https://auth.example.com/oauth/authorize?acr_values=mfa&max_age=60")!
    private let redirectUri = "com.frontegg.demo://auth.example.com/ios/oauth/callback"
    private let acrValues = "http://schemas.openid.net/pape/policies/2007/06/multi-factor"
    private let storages = ["localStorage", "sessionStorage"]

    private final class LoadWaiter: NSObject, WKNavigationDelegate {
        let finished: XCTestExpectation

        init(_ finished: XCTestExpectation) {
            self.finished = finished
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            finished.fulfill()
        }
    }

    private func loadPrelogin(redirectUriQueryValue: String, state: String = "session-state") async throws -> WKWebView {
        let contentController = WKUserContentController()
        contentController.addUserScript(WKUserScript(
            source: StepUpWebDriver.script(authorizeUrl: authorizeUrl),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)

        let encodedAcrValues = acrValues.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let preloginUrl = URL(string: "https://auth.example.com/oauth/prelogin?client_id=client&state=\(state)"
            + "&redirect_uri=\(redirectUriQueryValue)&acr_values=\(encodedAcrValues)&max_age=60")!

        let finished = expectation(description: "prelogin document loaded")
        let waiter = LoadWaiter(finished)
        webView.navigationDelegate = waiter
        webView.loadHTMLString("<html><body></body></html>", baseURL: preloginUrl)
        await fulfillment(of: [finished], timeout: 10)
        withExtendedLifetime(waiter) {}
        return webView
    }

    private func storedValue(_ key: String, in storage: String, of webView: WKWebView) async throws -> String? {
        try await webView.evaluateJavaScript("window.\(storage).getItem('\(key)')") as? String
    }

    func test_preloginDocument_savesTheParamsTheHostedPostloginNeeds() async throws {
        let encodedRedirectUri = redirectUri.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let webView = try await loadPrelogin(redirectUriQueryValue: encodedRedirectUri)

        for storage in storages {
            let savedRedirectUri = try await storedValue("FRONTEGG_OAUTH_REDIRECT_AFTER_LOGIN", in: storage, of: webView)
            let savedState = try await storedValue("FRONTEGG_OAUTH_STATE_AFTER_LOGIN", in: storage, of: webView)
            let savedAcrValues = try await storedValue("FRONTEGG_OAUTH_STEP_UP_ACR_VALUES", in: storage, of: webView)
            let savedMaxAge = try await storedValue("FRONTEGG_OAUTH_STEP_UP_MAX_AGE", in: storage, of: webView)
            XCTAssertEqual(savedRedirectUri, redirectUri, storage)
            XCTAssertEqual(savedState, "session-state", storage)
            XCTAssertEqual(savedAcrValues, acrValues, storage)
            XCTAssertEqual(savedMaxAge, "60", storage)
        }
    }

    func test_preloginDocument_routesToTheHostedRootSoStepUpOpensOnlyOnceAuthenticated() async throws {
        let encodedRedirectUri = redirectUri.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let webView = try await loadPrelogin(redirectUriQueryValue: encodedRedirectUri)

        let pathname = try await webView.evaluateJavaScript("window.location.pathname") as? String
        let shouldStepUp = try await storedValue("SHOULD_STEP_UP", in: "localStorage", of: webView)
        XCTAssertEqual(pathname, "/oauth/")
        XCTAssertEqual(shouldStepUp, "true")
    }

    func test_preloginDocument_decodesAnEncodedRedirectUriLikeTheHostedPage() async throws {
        let doubleEncodedRedirectUri = redirectUri
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let webView = try await loadPrelogin(redirectUriQueryValue: doubleEncodedRedirectUri)

        let savedRedirectUri = try await storedValue("FRONTEGG_OAUTH_REDIRECT_AFTER_LOGIN", in: "localStorage", of: webView)
        XCTAssertEqual(savedRedirectUri, redirectUri)
    }

    func test_preloginDocumentWithoutState_savesNoRedirectUriButStillRoutesToTheHostedRoot() async throws {
        let encodedRedirectUri = redirectUri.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let webView = try await loadPrelogin(redirectUriQueryValue: encodedRedirectUri, state: "")

        let savedRedirectUri = try await storedValue("FRONTEGG_OAUTH_REDIRECT_AFTER_LOGIN", in: "localStorage", of: webView)
        let savedState = try await storedValue("FRONTEGG_OAUTH_STATE_AFTER_LOGIN", in: "localStorage", of: webView)
        XCTAssertNil(savedRedirectUri)
        XCTAssertNil(savedState)
        let pathname = try await webView.evaluateJavaScript("window.location.pathname") as? String
        XCTAssertEqual(pathname, "/oauth/")
    }
}
