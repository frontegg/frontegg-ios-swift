import XCTest
@testable import FronteggSwift

final class LoginBoxFooterTests: XCTestCase {

    private func footerPayload(
        url: String = "https://policies.google.com/privacy",
        hideBadge: Bool = true
    ) -> [String: Any] {
        [
            "hideCaptchaBadge": hideBadge,
            "rows": [
                ["variant": "fine", "segments": [
                    ["text": "Protected by reCAPTCHA — "],
                    ["label": "Privacy Policy", "url": url]
                ]]
            ]
        ]
    }

    func testFooterAloneIsEnoughToInjectAScript() throws {
        let script = try XCTUnwrap(LoginBoxFooter.script(footerPayload()))

        XCTAssertTrue(script.contains("https://policies.google.com/privacy"))
    }

    func testScriptAssignsTheGlobalTheLoginBoxReads() throws {
        let script = try XCTUnwrap(LoginBoxFooter.script(footerPayload()))

        XCTAssertTrue(script.hasPrefix("window.__fronteggLoginBoxFooter = {"))
        XCTAssertTrue(script.hasSuffix("};"))
        XCTAssertFalse(script.contains("document."))
    }

    func testBadgeIsOnlyHiddenWhenAsked() throws {
        let hiding = try XCTUnwrap(LoginBoxFooter.script(footerPayload(hideBadge: true)))
        XCTAssertTrue(hiding.contains("\"hideCaptchaBadge\":true"))

        let notHiding = try XCTUnwrap(LoginBoxFooter.script(footerPayload(hideBadge: false)))
        XCTAssertTrue(notHiding.contains("\"hideCaptchaBadge\":false"))
    }

    func testQuotesInFooterCopyDoNotBreakTheScript() throws {
        let script = try XCTUnwrap(LoginBoxFooter.script([
            "rows": [["variant": "body", "segments": [["text": "Don't \"stop\""]]]]
        ]))

        XCTAssertTrue(script.contains("Don't \\\"stop\\\""))
    }

    // MARK: - Footer validation

    func testUnsafeSchemesDegradeToPlainText() throws {
        for url in [
            "javascript:alert(1)",
            "data:text/html,<script>alert(1)</script>",
            "file:///etc/passwd",
            "definitelynotregistered://sign-up"
        ] {
            let sanitized = try XCTUnwrap(
                LoginBoxFooter.sanitizedFooter(footerPayload(url: url)),
                "expected \(url) to still produce a footer"
            )
            let rows = try XCTUnwrap(sanitized["rows"] as? [[String: Any]])
            let segments = try XCTUnwrap(rows[0]["segments"] as? [[String: Any]])

            XCTAssertEqual(segments.count, 2, "expected \(url) to keep both segments")
            XCTAssertEqual(segments[1]["text"] as? String, "Privacy Policy")
            XCTAssertNil(segments[1]["url"], "expected \(url) to be stripped")
        }
    }

    func testHttpAndHttpsLinksAreAccepted() {
        XCTAssertEqual(
            LoginBoxFooter.sanitizedLinkUrl("https://app.example.com/x"),
            "https://app.example.com/x"
        )
        XCTAssertEqual(
            LoginBoxFooter.sanitizedLinkUrl("http://localhost:3000/x"),
            "http://localhost:3000/x"
        )
        XCTAssertEqual(
            LoginBoxFooter.sanitizedLinkUrl("HTTPS://app.example.com/x"),
            "HTTPS://app.example.com/x"
        )
    }

    func testRelativeAndEmptyLinksAreRejected() {
        XCTAssertNil(LoginBoxFooter.sanitizedLinkUrl("/users/sign_up/select"))
        XCTAssertNil(LoginBoxFooter.sanitizedLinkUrl(""))
        XCTAssertNil(LoginBoxFooter.sanitizedLinkUrl(nil))
        XCTAssertNil(LoginBoxFooter.sanitizedLinkUrl("https://"))
    }

    func testRegisteredAppSchemesAreAccepted() {
        XCTAssertEqual(
            LoginBoxFooter.sanitizedLinkUrl("myapp://sign-up", appSchemes: ["myapp"]),
            "myapp://sign-up"
        )
        XCTAssertEqual(
            LoginBoxFooter.sanitizedLinkUrl("MyApp://sign-up", appSchemes: ["myapp"]),
            "MyApp://sign-up"
        )
        XCTAssertEqual(
            LoginBoxFooter.sanitizedLinkUrl("myapp://sign-up", appSchemes: ["MyApp"]),
            "myapp://sign-up"
        )
        XCTAssertNil(LoginBoxFooter.sanitizedLinkUrl("otherapp://sign-up", appSchemes: ["myapp"]))
    }

    func testOAuthShapedAppSchemeLinksAreRejected() {
        for url in [
            "myapp://sign-up?code=INVITE",
            "myapp://sign-up?error=x",
            "myapp://sign-up?error_description=x",
            "myapp://app/#/sign-up?code=INVITE"
        ] {
            XCTAssertNil(LoginBoxFooter.sanitizedLinkUrl(url, appSchemes: ["myapp"]), url)
        }
        XCTAssertEqual(
            LoginBoxFooter.sanitizedLinkUrl("myapp://sign-up?plan=pro", appSchemes: ["myapp"]),
            "myapp://sign-up?plan=pro"
        )
    }

    func testDeniedSchemesStayRejectedWhenTheAppRegistersThem() {
        XCTAssertNil(LoginBoxFooter.sanitizedLinkUrl("data:text/html,x", appSchemes: ["data"]))
        XCTAssertNil(LoginBoxFooter.sanitizedLinkUrl("javascript:alert(1)", appSchemes: ["javascript"]))
    }

    func testAppSchemeLinkSurvivesSanitizingButIsNotOpenedExternally() throws {
        let footer: [String: Any] = ["rows": [["variant": "body", "segments": [
            ["label": "Sign up", "url": "myapp://sign-up"]
        ]]]]

        let sanitized = try XCTUnwrap(LoginBoxFooter.sanitizedFooter(footer, appSchemes: ["myapp"]))
        let rows = try XCTUnwrap(sanitized["rows"] as? [[String: Any]])
        let segments = try XCTUnwrap(rows[0]["segments"] as? [[String: Any]])
        XCTAssertEqual(segments[0]["url"] as? String, "myapp://sign-up")

        XCTAssertTrue(LoginBoxFooter.footerExternalUrls(footer, appSchemes: ["myapp"]).isEmpty)
    }

    func testEmptyFooterProducesNothing() {
        XCTAssertNil(LoginBoxFooter.sanitizedFooter(nil))
        XCTAssertNil(LoginBoxFooter.sanitizedFooter([:]))
        XCTAssertNil(LoginBoxFooter.sanitizedFooter(["rows": []]))
        XCTAssertNil(LoginBoxFooter.sanitizedFooter([
            "rows": [["variant": "body", "segments": [["label": ""], ["text": ""]]]]
        ]))
    }

    func testUnknownVariantFallsBackToBody() throws {
        let sanitized = try XCTUnwrap(LoginBoxFooter.sanitizedFooter([
            "rows": [["variant": "enormous", "segments": [["text": "hi"]]]]
        ]))
        let rows = try XCTUnwrap(sanitized["rows"] as? [[String: Any]])

        XCTAssertEqual(rows[0]["variant"] as? String, "body")
    }

    // MARK: - External link allowlist

    func testExternalUrlsCoverOnlyHttpLinks() {
        let urls = LoginBoxFooter.footerExternalUrls([
            "rows": [["variant": "body", "segments": [
                ["label": "Privacy", "url": "https://policies.google.com/privacy"],
                ["label": "Terms", "url": "http://example.com/terms"],
                ["label": "Sign up", "url": "myapp://sign-up"],
                ["text": "no link here"]
            ]]]
        ])

        XCTAssertEqual(urls, [
            "https://policies.google.com/privacy",
            "http://example.com/terms"
        ])
    }

    func testExternalFooterLinkMatchesWebKitCanonicalForm() throws {
        let footer = footerPayload(url: "HTTPS://Policies.Google.com:443")
        let navigatedUrl = try XCTUnwrap(URL(string: "https://policies.google.com/"))

        XCTAssertTrue(LoginBoxFooter.isExternalFooterLink(navigatedUrl, externalUrls: LoginBoxFooter.footerExternalUrls(footer)))
    }

    func testExternalFooterLinkResolvesDotSegments() throws {
        let footer = footerPayload(url: "https://policies.google.com/legal/../privacy")
        let navigatedUrl = try XCTUnwrap(URL(string: "https://policies.google.com/privacy"))

        XCTAssertTrue(LoginBoxFooter.isExternalFooterLink(navigatedUrl, externalUrls: LoginBoxFooter.footerExternalUrls(footer)))
    }

    func testExternalFooterLinkDoesNotMatchOtherUrls() throws {
        let footer = footerPayload(url: "https://policies.google.com/privacy")
        let otherUrl = try XCTUnwrap(URL(string: "https://policies.google.com/terms"))

        XCTAssertFalse(LoginBoxFooter.isExternalFooterLink(otherUrl, externalUrls: LoginBoxFooter.footerExternalUrls(footer)))
        XCTAssertFalse(LoginBoxFooter.isExternalFooterLink(otherUrl, externalUrls: []))
    }

    func testAppSchemeMatchingIgnoresCase() {
        XCTAssertTrue(CustomWebView.isAppUrlScheme("myapp", appSchemes: ["MyApp"]))
        XCTAssertTrue(CustomWebView.isAppUrlScheme("MyApp", appSchemes: ["myapp"]))
        XCTAssertFalse(CustomWebView.isAppUrlScheme("otherapp", appSchemes: ["MyApp"]))
        XCTAssertFalse(CustomWebView.isAppUrlScheme("myapp", appSchemes: []))
    }

    func testRejectedLinkUrlsListsOnlyUrlsThatRenderAsText() {
        let footer: [String: Any] = ["rows": [["variant": "body", "segments": [
            ["label": "Privacy", "url": "https://policies.google.com/privacy"],
            ["label": "Script", "url": "javascript:alert(1)"],
            ["label": "Unregistered", "url": "definitelynotregistered://sign-up"],
            ["text": "plain text"]
        ]]]]

        XCTAssertEqual(
            LoginBoxFooter.rejectedLinkUrls(footer),
            ["javascript:alert(1)", "definitelynotregistered://sign-up"]
        )
        XCTAssertTrue(LoginBoxFooter.rejectedLinkUrls(nil).isEmpty)
    }

    func testRejectedLinkUrlsReportsNonStringUrls() throws {
        let urlObject = try XCTUnwrap(URL(string: "https://policies.google.com/privacy"))
        let footer: [String: Any] = ["rows": [["variant": "body", "segments": [
            ["label": "Privacy", "url": urlObject]
        ]]]]

        XCTAssertEqual(LoginBoxFooter.rejectedLinkUrls(footer), ["https://policies.google.com/privacy"])
    }

    func testRejectedLinkUrlsOmitQueryAndFragment() {
        let footer: [String: Any] = ["rows": [["variant": "body", "segments": [
            ["label": "Invite", "url": "definitelynotregistered://sign-up?code=INVITE#ref=abc"]
        ]]]]

        XCTAssertEqual(LoginBoxFooter.rejectedLinkUrls(footer), ["definitelynotregistered://sign-up"])
    }

    func testOAuthCallbackParameterInFragmentIsDetected() {
        XCTAssertTrue(LoginBoxFooter.carriesOAuthCallbackParameter("myapp://app/#/sign-up?code=INVITE"))
        XCTAssertTrue(LoginBoxFooter.carriesOAuthCallbackParameter("myapp://sign-up?plan=pro#&error=x"))
        XCTAssertTrue(LoginBoxFooter.carriesOAuthCallbackParameter("myapp://sign-up?code=INVITE"))
        XCTAssertFalse(LoginBoxFooter.carriesOAuthCallbackParameter("myapp://sign-up?plan=pro#section"))
    }

    func testExternalUrlsAreEmptyWithoutAFooter() {
        XCTAssertTrue(LoginBoxFooter.footerExternalUrls(nil).isEmpty)
        XCTAssertTrue(LoginBoxFooter.footerExternalUrls(["rows": []]).isEmpty)
    }

    func testExternalUrlsExcludeRejectedLinks() {
        XCTAssertTrue(
            LoginBoxFooter.footerExternalUrls(
                footerPayload(url: "javascript:alert(1)")
            ).isEmpty
        )
    }

    func testNoFooterProducesNoScript() {
        XCTAssertNil(LoginBoxFooter.script(nil))
        XCTAssertNil(LoginBoxFooter.script(["rows": []]))
    }
}
