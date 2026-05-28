//
//  PermissionMatcher.swift
//  FronteggSwift
//
//  Port of `checkPermission` from @frontegg/entitlements-javascript-commons.
//

import Foundation

enum PermissionMatcher {
    /// The server returns granted permissions as concrete strings OR wildcard
    /// patterns (e.g. `fe.secure.*`); the host app asks about a concrete required
    /// permission (e.g. `fe.secure.read.users`). Match if any granted key, when its
    /// wildcards are turned into `.*`, regex-matches the requested key.
    ///
    /// The regex is anchored — `^…$` — so `fe.secure.*` does NOT match
    /// `prefix.fe.secure.x`. Dots are escaped to literals; `*` is the only
    /// wildcard.
    static func hasPermission(_ granted: [String: Bool], required: String) -> Bool {
        let truthy = granted.filter { $0.value }.map { $0.key }
        for key in truthy where matches(pattern: key, value: required) {
            return true
        }
        return false
    }

    private static func matches(pattern: String, value: String) -> Bool {
        var escaped = "^"
        for ch in pattern {
            switch ch {
            case "*": escaped += ".*"
            case ".": escaped += "\\."
            // Defensive — escape other regex metacharacters so a malformed permission
            // key can't ReDoS the SDK.
            case "+", "?", "(", ")", "[", "]", "{", "}", "|", "^", "$", "\\":
                escaped.append("\\")
                escaped.append(ch)
            default: escaped.append(ch)
            }
        }
        escaped += "$"
        guard let regex = try? NSRegularExpression(pattern: escaped, options: [.dotMatchesLineSeparators]) else {
            return false
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, options: [], range: range) != nil
    }
}
