//
//  EncodingUtils.swift
//
//
//  Created by David Antoon on 23/10/2024.
//

import Foundation


extension String {
    // MARK: - Base64 Decoding Utility

    /// A helper function to decode a Base64URL encoded string into Data.
    /// - Parameter input: The Base64URL string to be decoded.
    /// - Returns: The decoded Data if successful, otherwise nil.

    func toDecodedData() -> Data? {
        var base64 = self.replacingOccurrences(of: "-", with: "+")
                         .replacingOccurrences(of: "_", with: "/")
        let paddingLength = 4 - (base64.count % 4)
        if paddingLength < 4 {
            base64 += String(repeating: "=", count: paddingLength)
        }
        return Data(base64Encoded: base64)
    }
}

extension Data {
    // MARK: - Base64 Encoding Utility

    /// A helper function to encode Data into a Base64URL encoded string.
    /// Base64URL replaces "+" with "-" and "/" with "_", and removes the padding ("=").
    /// - Parameter inputData: The data to be encoded into Base64URL format.
    /// - Returns: A Base64URL encoded string
    func toEncodedBase64() -> String {
        var base64 = self.base64EncodedString()
        base64 = base64.replacingOccurrences(of: "+", with: "-")
                       .replacingOccurrences(of: "/", with: "_")
                       .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        return base64
    }
}

func createRandomString(_ length: Int = 16) -> String {
    let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    return String((0 ..< length).map{ _ in letters.randomElement()! })
}
