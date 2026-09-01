import XCTest
@testable import FronteggSwift

/// Covers the script builder that applies host-supplied theme/copy overrides to
/// the embedded login box.
final class LoginBoxCustomizationTests: XCTestCase {

    // MARK: - No-op cases

    func testReturnsNilWhenNothingProvided() {
        XCTAssertNil(LoginBoxCustomization.script(themeOptions: nil, localizations: nil))
    }

    func testReturnsNilWhenOverridesAreEmpty() {
        XCTAssertNil(LoginBoxCustomization.script(themeOptions: [:], localizations: [:]))
    }

    func testReturnsNilWhenValuesAreNotJSONSerializable() {
        // Date is not a valid JSON type; the builder must refuse rather than
        // emit a script that throws inside the WebView.
        XCTAssertNil(LoginBoxCustomization.script(themeOptions: ["logo": Date()], localizations: nil))
    }

    // MARK: - Payload

    func testThemeOptionsAreEmittedUnderThemeV2() throws {
        let script = try XCTUnwrap(LoginBoxCustomization.script(
            themeOptions: ["loginBox": ["palette": ["primary": ["main": "#3F6655"]]]],
            localizations: nil
        ))

        XCTAssertTrue(script.contains("\"themeV2\""))
        XCTAssertTrue(script.contains("#3F6655"))
        XCTAssertFalse(script.contains("\"localizations\""))
    }

    func testLocalizationsAreEmittedUnderLocalizations() throws {
        let script = try XCTUnwrap(LoginBoxCustomization.script(
            themeOptions: nil,
            localizations: ["en": ["loginBox": ["login": ["title": "Sign-in"]]]]
        ))

        XCTAssertTrue(script.contains("\"localizations\""))
        XCTAssertTrue(script.contains("Sign-in"))
        XCTAssertFalse(script.contains("\"themeV2\""))
    }

    func testBothOverridesAreEmittedTogether() throws {
        let script = try XCTUnwrap(LoginBoxCustomization.script(
            themeOptions: ["loginBox": ["logo": ["image": "https://example.com/logo.png"]]],
            localizations: ["en": ["loginBox": ["login": ["continue": "Log In"]]]]
        ))

        XCTAssertTrue(script.contains("\"themeV2\""))
        XCTAssertTrue(script.contains("\"localizations\""))
        // JSONSerialization escapes forward slashes, so the URL appears as
        // `https:\/\/example.com\/logo.png`. See testLogoURLSurvivesSlashEscaping.
        XCTAssertTrue(script.contains("example.com"))
        XCTAssertTrue(script.contains("logo.png"))
        XCTAssertTrue(script.contains("Log In"))
    }

    /// JSONSerialization writes `/` as `\/`. That is valid JSON and decodes back
    /// to the original URL, so the login box still receives a usable logo source.
    func testLogoURLSurvivesSlashEscaping() throws {
        let url = "https://example.com/assets/logo.png"
        let json = try XCTUnwrap(LoginBoxCustomization.encodeOverrides(
            ["themeV2": ["loginBox": ["logo": ["image": url]]]]
        ))

        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let themeV2 = try XCTUnwrap(decoded?["themeV2"] as? [String: Any])
        let loginBox = try XCTUnwrap(themeV2["loginBox"] as? [String: Any])
        let logo = try XCTUnwrap(loginBox["logo"] as? [String: Any])

        XCTAssertEqual(logo["image"] as? String, url)
    }

    // MARK: - Script shape

    func testScriptTargetsTheLoginBoxMetadataRequest() throws {
        let script = try XCTUnwrap(LoginBoxCustomization.script(
            themeOptions: ["loginBox": ["themeName": "modern"]],
            localizations: nil
        ))

        XCTAssertTrue(script.contains(LoginBoxCustomization.metadataPath))
        XCTAssertTrue(script.contains("window.fetch"))
        // Guards against double-installing when the script is injected twice.
        XCTAssertTrue(script.contains("__fronteggLoginBoxOverridesInstalled"))
        // The placeholder must always be substituted.
        XCTAssertFalse(script.contains("__FRONTEGG_OVERRIDES__"))
    }

    // MARK: - Encoding

    func testEncodingEscapesJavaScriptLineTerminators() throws {
        // U+2028/U+2029 are valid JSON but terminate a line in JavaScript source,
        // which would break the emitted script.
        let json = try XCTUnwrap(LoginBoxCustomization.encodeOverrides(
            ["localizations": ["en": ["note": "a\u{2028}b\u{2029}c"]]]
        ))

        XCTAssertFalse(json.contains("\u{2028}"))
        XCTAssertFalse(json.contains("\u{2029}"))
        XCTAssertTrue(json.contains("\\u2028"))
        XCTAssertTrue(json.contains("\\u2029"))
    }

    func testEncodedOverridesRoundTripAsJSON() throws {
        let overrides: [String: Any] = ["themeV2": ["loginBox": ["palette": ["primary": ["main": "#16284A"]]]]]
        let json = try XCTUnwrap(LoginBoxCustomization.encodeOverrides(overrides))

        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let themeV2 = try XCTUnwrap(decoded?["themeV2"] as? [String: Any])
        let loginBox = try XCTUnwrap(themeV2["loginBox"] as? [String: Any])
        let palette = try XCTUnwrap(loginBox["palette"] as? [String: Any])
        let primary = try XCTUnwrap(palette["primary"] as? [String: Any])

        XCTAssertEqual(primary["main"] as? String, "#16284A")
    }

    func testQuotesInCopyDoNotBreakTheScript() throws {
        let script = try XCTUnwrap(LoginBoxCustomization.script(
            themeOptions: nil,
            localizations: ["en": ["loginBox": ["login": ["title": "Don't \"stop\" now"]]]]
        ))

        // JSONSerialization escapes the double quotes; the apostrophe is safe
        // because the payload is embedded as an object literal, not a string.
        XCTAssertTrue(script.contains("Don't \\\"stop\\\" now"))
    }
}
