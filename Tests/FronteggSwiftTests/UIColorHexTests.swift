//
//  UIColorHexTests.swift
//  FronteggSwiftTests
//

import XCTest
import UIKit
@testable import FronteggSwift

final class UIColorHexTests: XCTestCase {

    func test_hexString_parsesSixDigitsAsOpaque() throws {
        let color = try XCTUnwrap(UIColor(hexString: "#FF8000"))
        assertComponents(of: color, red: 1, green: 128.0 / 255, blue: 0, alpha: 1)
    }

    func test_hexString_parsesEightDigitsWithAlpha() throws {
        let color = try XCTUnwrap(UIColor(hexString: "#00000080"))
        assertComponents(of: color, red: 0, green: 0, blue: 0, alpha: 128.0 / 255)
    }

    func test_hexString_acceptsMissingHashAndSurroundingWhitespace() throws {
        let color = try XCTUnwrap(UIColor(hexString: "  ffffff \n"))
        assertComponents(of: color, red: 1, green: 1, blue: 1, alpha: 1)
    }

    func test_hexString_rejectsInvalidValues() {
        for invalidValue in ["", "#", "#FFF", "#FFFFF", "#GGGGGG", "#+FFFFF", "#FFFFFFF", "white"] {
            XCTAssertNil(UIColor(hexString: invalidValue), "expected \(invalidValue.debugDescription) to be rejected")
        }
    }

    func test_fronteggBackgroundColor_isNilWhenUnset() {
        XCTAssertNil(UIColor.fronteggBackgroundColor(from: nil))
    }

    func test_fronteggBackgroundColor_resolvesDocumentedHexFormat() throws {
        let color = try XCTUnwrap(UIColor.fronteggBackgroundColor(from: "#1A2B3C"))
        assertComponents(of: color, red: 0x1A / 255.0, green: 0x2B / 255.0, blue: 0x3C / 255.0, alpha: 1)
    }

    func test_fronteggBackgroundColor_isNilForUnknownAssetName() {
        XCTAssertNil(UIColor.fronteggBackgroundColor(from: "NotAnAssetCatalogColor"))
    }

    private func assertComponents(
        of color: UIColor,
        red expectedRed: CGFloat,
        green expectedGreen: CGFloat,
        blue expectedBlue: CGFloat,
        alpha expectedAlpha: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha), file: file, line: line)
        XCTAssertEqual(red, expectedRed, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(green, expectedGreen, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(blue, expectedBlue, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(alpha, expectedAlpha, accuracy: 0.001, file: file, line: line)
    }
}
