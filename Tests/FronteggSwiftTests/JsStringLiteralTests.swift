//
//  JsStringLiteralTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

/// FR-26113 / #288: the embedded passkey bridge interpolated `error.localizedDescription`
/// raw into `evaluateJavaScript("…reject(\"\(msg)\")")`. Any `"`, `\` or newline in the
/// message broke the injected statement, so `reject(...)` never ran and the page's
/// credential promise hung. `jsStringLiteral` must emit a quoted, fully-escaped literal
/// that stays valid JS for every input.
final class JsStringLiteralTests: XCTestCase {

    /// Decodes a JS/JSON string literal back to its Swift value (nil if not a valid literal).
    private func decode(_ literal: String) -> String? {
        (try? JSONSerialization.jsonObject(with: Data(literal.utf8), options: [.fragmentsAllowed])) as? String
    }

    /// Every input must produce a double-quoted literal that round-trips to the original.
    private func assertRoundTrips(_ input: String, file: StaticString = #filePath, line: UInt = #line) {
        let literal = FronteggWKContentController.jsStringLiteral(input)
        XCTAssertTrue(literal.hasPrefix("\"") && literal.hasSuffix("\""),
                      "expected a quoted literal, got: \(literal)", file: file, line: line)
        XCTAssertEqual(decode(literal), input,
                       "literal did not round-trip to the input: \(literal)", file: file, line: line)
    }

    func test_plainMessage_roundTrips() {
        assertRoundTrips("Unknown error occurred")
    }

    /// The actual bug: an unescaped `"` produced `reject("say "hi"")` — a syntax error that
    /// never executed. The inner quotes must be backslash-escaped.
    func test_doubleQuote_isEscaped() {
        let literal = FronteggWKContentController.jsStringLiteral("say \"hi\"")
        XCTAssertTrue(literal.contains("\\\""),
                      "inner double-quotes must be backslash-escaped, got: \(literal)")
        assertRoundTrips("say \"hi\"")
    }

    func test_backslash_isEscaped() {
        assertRoundTrips("path\\to\\thing")
    }

    /// A raw newline in the injected statement is a JS syntax error; it must be escaped.
    func test_newline_isEscaped() {
        let literal = FronteggWKContentController.jsStringLiteral("line1\nline2")
        XCTAssertFalse(literal.contains("\n"),
                       "a raw newline must not survive into the literal, got: \(literal)")
        assertRoundTrips("line1\nline2")
    }

    func test_combinedSpecialCharacters_roundTrip() {
        assertRoundTrips("err \"x\" \\ y \n z \t end")
    }

    func test_emptyString_isEmptyQuotedLiteral() {
        XCTAssertEqual(FronteggWKContentController.jsStringLiteral(""), "\"\"")
    }

    func test_controlCharacters_areEscaped() {
        assertRoundTrips("bell\u{07}sep\u{01}end")
    }

    /// U+2028 / U+2029 are valid in JSON but technically invalid *unescaped* in a JS string
    /// literal. `JSONSerialization` does not escape them, so this documents current behaviour
    /// (the literal still round-trips). If `jsStringLiteral` is later hardened to escape them,
    /// this test stays green.
    func test_lineAndParagraphSeparators_roundTrip() {
        assertRoundTrips("a\u{2028}b\u{2029}c")
    }
}
