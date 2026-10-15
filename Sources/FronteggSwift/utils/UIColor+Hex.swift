//
//  UIColor+Hex.swift
//  FronteggSwift
//

import UIKit

extension UIColor {

    /// Parses `#RRGGBB` or `#RRGGBBAA`, with or without the leading `#`.
    convenience init?(hexString: String) {
        let trimmed = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        let hexDigits = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard hexDigits.count == 6 || hexDigits.count == 8,
              hexDigits.allSatisfy(\.isHexDigit),
              let packedValue = UInt64(hexDigits, radix: 16) else {
            return nil
        }

        let hasAlpha = hexDigits.count == 8
        let rgbValue = hasAlpha ? packedValue >> 8 : packedValue
        let alphaValue = hasAlpha ? packedValue & 0xFF : 0xFF

        self.init(
            red: CGFloat((rgbValue >> 16) & 0xFF) / 255,
            green: CGFloat((rgbValue >> 8) & 0xFF) / 255,
            blue: CGFloat(rgbValue & 0xFF) / 255,
            alpha: CGFloat(alphaValue) / 255
        )
    }

    /// Resolves the plist `backgroundColor`: a hex string, or an asset-catalog color name.
    static func fronteggBackgroundColor(from configuredValue: String?) -> UIColor? {
        guard let configuredValue else { return nil }
        return UIColor(named: configuredValue) ?? UIColor(hexString: configuredValue)
    }
}
