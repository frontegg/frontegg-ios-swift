//
//  LoginBoxCustomization.swift
//

import Foundation

/// Builds the document-start script that hands app-supplied `themeV2` and
/// `localizations` overrides to the hosted login box.
///
/// The box reads `window.__fronteggLoginBoxOverrides` and deep-merges it over the
/// environment's own configuration. See `applyHostOverrides` in oauth-service.
enum LoginBoxCustomization {

    static let globalName = "__fronteggLoginBoxOverrides"

    /// Returns `nil` when there is nothing to override or the values cannot be
    /// represented in JSON, so callers can skip injecting a script entirely.
    static func script(themeOptions: [String: Any]?, localizations: [String: Any]?) -> String? {
        var overrides: [String: Any] = [:]

        if let themeOptions, !themeOptions.isEmpty {
            overrides["themeV2"] = themeOptions
        }
        if let localizations, !localizations.isEmpty {
            overrides["localizations"] = localizations
        }

        guard !overrides.isEmpty, let json = encodeOverrides(overrides) else {
            return nil
        }
        return "window.\(globalName) = \(json);"
    }

    static func encodeOverrides(_ overrides: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(overrides),
              let data = try? JSONSerialization.data(withJSONObject: overrides, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }

        return json
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    /// Key path of the first value that cannot be represented in JSON, or `nil` when
    /// the whole value is encodable. Used to name the offending key instead of
    /// dropping the overrides without explanation.
    static func invalidKeyPath(in value: Any, path: String = "") -> String? {
        switch value {
        case is String, is NSNull:
            return nil
        case is NSNumber:
            return nil
        case let dictionary as [String: Any]:
            for key in dictionary.keys.sorted() {
                let childPath = path.isEmpty ? key : "\(path).\(key)"
                if let found = invalidKeyPath(in: dictionary[key] as Any, path: childPath) {
                    return found
                }
            }
            return nil
        case let array as [Any]:
            for (index, element) in array.enumerated() {
                if let found = invalidKeyPath(in: element, path: "\(path)[\(index)]") {
                    return found
                }
            }
            return nil
        default:
            return path.isEmpty ? "<root>" : path
        }
    }
}
