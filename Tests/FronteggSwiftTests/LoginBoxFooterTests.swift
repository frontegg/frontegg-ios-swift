import XCTest
@testable import FronteggSwift

/// Covers the script builder and validation for the host-supplied footer below
/// the embedded login box's card.
final class LoginBoxFooterTests: XCTestCase {

    /// A footer with one usable row, for tests that only care that it is valid.
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
        // The footer stands on its own: an app can add an attribution without
        // overriding any theme or copy.
        let script = try XCTUnwrap(LoginBoxFooter.script(footerPayload()))

        XCTAssertTrue(script.contains("https://policies.google.com/privacy"))
        XCTAssertTrue(script.contains("[data-test-id=\"root-element\"]"))
    }

    func testBadgeIsOnlyHiddenWhenAsked() throws {
        let hiding = try XCTUnwrap(LoginBoxFooter.script(footerPayload(hideBadge: true)))
        XCTAssertTrue(hiding.contains("\"hideCaptchaBadge\":true"))

        let notHiding = try XCTUnwrap(LoginBoxFooter.script(footerPayload(hideBadge: false)))
        XCTAssertTrue(notHiding.contains("\"hideCaptchaBadge\":false"))
    }

    /// Host copy must never be interpreted as markup.
    func testFooterCopyIsRenderedAsTextNotHtml() throws {
        let script = try XCTUnwrap(LoginBoxFooter.script(footerPayload()))

        XCTAssertTrue(script.contains("anchor.textContent = segment.label;"))
        XCTAssertTrue(script.contains("createTextNode(segment.text)"))
        // Asserted as an assignment rather than a bare substring, so the
        // comment in the script explaining why we avoid it doesn't trip this.
        XCTAssertFalse(script.contains(".innerHTML ="))
        XCTAssertFalse(script.contains("insertAdjacentHTML"))
    }

    /// The footer follows the login screen only, matching the React SDK where
    /// `boxFooter` is configured under `login`.
    func testFooterIsScopedToTheLoginScreen() throws {
        let script = try XCTUnwrap(LoginBoxFooter.script(footerPayload()))

        XCTAssertTrue(script.contains("[data-test-id=\"login-page-title\"]"))
    }

    func testQuotesInFooterCopyDoNotBreakTheScript() throws {
        let script = try XCTUnwrap(LoginBoxFooter.script([
            "rows": [["variant": "body", "segments": [["text": "Don't \"stop\""]]]]
        ]))

        XCTAssertTrue(script.contains("Don't \\\"stop\\\""))
    }

    // MARK: - Footer validation

    /// A bad URL degrades the segment to plain text rather than dropping it: a
    /// legal attribution missing a fragment reads as a bug, whereas an unlinked
    /// label still says what it needs to say.
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
        // http is allowed for local development against a plain-HTTP host.
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

    /// A host that presents its own sign-up flow outside this WebView points a
    /// footer link at its own scheme; the delegate's custom-scheme branch then
    /// opens it and dismisses the box.
    func testAppRegisteredSchemesAreAccepted() {
        // The test bundle registers none, so this asserts the mechanism rather
        // than a specific scheme: whatever the bundle declares is accepted, and
        // anything else is not.
        let schemes = LoginBoxFooter.appUrlSchemes()

        if let scheme = schemes.first {
            XCTAssertEqual(
                LoginBoxFooter.sanitizedLinkUrl("\(scheme)://sign-up"),
                "\(scheme)://sign-up"
            )
        }
        XCTAssertFalse(schemes.contains("definitelynotregistered"))
        XCTAssertNil(LoginBoxFooter.sanitizedLinkUrl("definitelynotregistered://sign-up"))
    }

    func testEmptyFooterProducesNothing() {
        XCTAssertNil(LoginBoxFooter.sanitizedFooter(nil))
        XCTAssertNil(LoginBoxFooter.sanitizedFooter([:]))
        XCTAssertNil(LoginBoxFooter.sanitizedFooter(["rows": []]))
        // Rows with no usable segments are dropped, and a footer with no
        // surviving rows is no footer at all.
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

    /// Only `http(s)` links leave for the OS. An app-scheme link is a hand-off
    /// the custom-scheme branch already owns, and must not be short-circuited
    /// into "open externally, keep the box mounted".
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

    func testExternalUrlsAreEmptyWithoutAFooter() {
        XCTAssertTrue(LoginBoxFooter.footerExternalUrls(nil).isEmpty)
        XCTAssertTrue(LoginBoxFooter.footerExternalUrls(["rows": []]).isEmpty)
    }

    /// A rejected URL must not linger in the allowlist, or the delegate would
    /// hand the OS a value the footer never rendered.
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
