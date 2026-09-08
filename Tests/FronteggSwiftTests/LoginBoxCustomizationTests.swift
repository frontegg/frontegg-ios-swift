import XCTest
@testable import FronteggSwift

final class LoginBoxCustomizationTests: XCTestCase {

    // MARK: - No-op cases

    func testReturnsNilWhenNothingProvided() {
        XCTAssertNil(LoginBoxCustomization.script(themeOptions: nil, localizations: nil))
    }

    func testReturnsNilWhenOverridesAreEmpty() {
        XCTAssertNil(LoginBoxCustomization.script(themeOptions: [:], localizations: [:]))
    }

    func testReturnsNilWhenValuesAreNotJSONSerializable() {
        XCTAssertNil(LoginBoxCustomization.script(themeOptions: ["logo": Date()], localizations: nil))
    }

    // MARK: - Payload

    func testAssignsOverridesToTheGlobalTheLoginBoxReads() throws {
        let script = try XCTUnwrap(LoginBoxCustomization.script(
            themeOptions: ["loginBox": ["palette": ["primary": ["main": "#3F6655"]]]],
            localizations: nil
        ))

        XCTAssertTrue(script.hasPrefix("window.__fronteggLoginBoxOverrides = "))
        XCTAssertTrue(script.hasSuffix(";"))
        XCTAssertFalse(script.contains("window.fetch"))
    }

    func testThemeOptionsAreEmittedUnderThemeV2() throws {
        let payload = try payloadOf(
            themeOptions: ["loginBox": ["palette": ["primary": ["main": "#3F6655"]]]],
            localizations: nil
        )

        let themeV2 = try XCTUnwrap(payload["themeV2"] as? [String: Any])
        let loginBox = try XCTUnwrap(themeV2["loginBox"] as? [String: Any])
        let palette = try XCTUnwrap(loginBox["palette"] as? [String: Any])
        let primary = try XCTUnwrap(palette["primary"] as? [String: Any])

        XCTAssertEqual(primary["main"] as? String, "#3F6655")
        XCTAssertNil(payload["localizations"])
    }

    func testLocalizationsAreEmittedUnderLocalizations() throws {
        let payload = try payloadOf(
            themeOptions: nil,
            localizations: ["en": ["loginBox": ["login": ["title": "Sign-in"]]]]
        )

        let localizations = try XCTUnwrap(payload["localizations"] as? [String: Any])
        let en = try XCTUnwrap(localizations["en"] as? [String: Any])
        let loginBox = try XCTUnwrap(en["loginBox"] as? [String: Any])
        let login = try XCTUnwrap(loginBox["login"] as? [String: Any])

        XCTAssertEqual(login["title"] as? String, "Sign-in")
        XCTAssertNil(payload["themeV2"])
    }

    func testBothOverridesAreEmittedTogether() throws {
        let payload = try payloadOf(
            themeOptions: ["loginBox": ["logo": ["image": "https://example.com/logo.png"]]],
            localizations: ["en": ["loginBox": ["login": ["continue": "Log In"]]]]
        )

        XCTAssertNotNil(payload["themeV2"])
        XCTAssertNotNil(payload["localizations"])
    }

    func testLogoURLSurvivesEncoding() throws {
        let url = "https://example.com/assets/logo.png"
        let payload = try payloadOf(
            themeOptions: ["loginBox": ["logo": ["image": url]]],
            localizations: nil
        )

        let themeV2 = try XCTUnwrap(payload["themeV2"] as? [String: Any])
        let loginBox = try XCTUnwrap(themeV2["loginBox"] as? [String: Any])
        let logo = try XCTUnwrap(loginBox["logo"] as? [String: Any])

        XCTAssertEqual(logo["image"] as? String, url)
    }

    // MARK: - Encoding

    func testEncodingEscapesJavaScriptLineTerminators() throws {
        let json = try XCTUnwrap(LoginBoxCustomization.encodeOverrides(
            ["localizations": ["en": ["note": "a\u{2028}b\u{2029}c"]]]
        ))

        XCTAssertFalse(json.contains("\u{2028}"))
        XCTAssertFalse(json.contains("\u{2029}"))
        XCTAssertTrue(json.contains("\\u2028"))
        XCTAssertTrue(json.contains("\\u2029"))
    }

    func testQuotesInCopyDoNotBreakTheScript() throws {
        let payload = try payloadOf(
            themeOptions: nil,
            localizations: ["en": ["loginBox": ["login": ["title": "Don't \"stop\" now"]]]]
        )

        let localizations = try XCTUnwrap(payload["localizations"] as? [String: Any])
        let en = try XCTUnwrap(localizations["en"] as? [String: Any])
        let loginBox = try XCTUnwrap(en["loginBox"] as? [String: Any])
        let login = try XCTUnwrap(loginBox["login"] as? [String: Any])

        XCTAssertEqual(login["title"] as? String, "Don't \"stop\" now")
    }

    // MARK: - Naming the unencodable value

    func testInvalidKeyPathIsNilForEncodableValues() {
        let value: [String: Any] = [
            "loginBox": [
                "palette": ["primary": ["main": "#3F6655"]],
                "enabled": true,
                "order": 3,
                "tags": ["a", "b"],
                "absent": NSNull(),
            ]
        ]

        XCTAssertNil(LoginBoxCustomization.invalidKeyPath(in: value))
    }

    func testInvalidKeyPathNamesTheOffendingKey() {
        let value: [String: Any] = ["loginBox": ["palette": ["primary": ["main": Date()]]]]

        XCTAssertEqual(
            LoginBoxCustomization.invalidKeyPath(in: value),
            "loginBox.palette.primary.main"
        )
    }

    func testInvalidKeyPathNamesTheOffendingArrayElement() {
        let value: [String: Any] = ["loginBox": ["tags": ["ok", Date()]]]

        XCTAssertEqual(LoginBoxCustomization.invalidKeyPath(in: value), "loginBox.tags[1]")
    }

    // MARK: - Helpers

    private func payloadOf(
        themeOptions: [String: Any]?,
        localizations: [String: Any]?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String: Any] {
        let script = try XCTUnwrap(
            LoginBoxCustomization.script(themeOptions: themeOptions, localizations: localizations),
            file: file,
            line: line
        )

        let prefix = "window.\(LoginBoxCustomization.globalName) = "
        var json = String(script.dropFirst(prefix.count))
        if json.hasSuffix(";") {
            json.removeLast()
        }

        let data = try XCTUnwrap(json.data(using: .utf8), file: file, line: line)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            file: file,
            line: line
        )
    }
}
