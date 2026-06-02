//
//  Operations.swift
//  FronteggSwift
//
//  Port of the operations + sanitizers matrix from
//  @frontegg/entitlements-javascript-commons. Two-step protocol:
//
//    1. `SanitizerResolver.sanitize` narrows the raw `condition.value` payload to
//       a strongly-typed payload. If the payload doesn't match the operation,
//       sanitization fails and the condition is treated as `false`.
//    2. `OperationResolver.resolve` returns a handler `(Any?) -> Bool` that runs
//       the operation against an attribute pulled out of the prepared map. Type
//       mismatches (e.g. operation expects String, attribute is Bool) return false.
//

import Foundation

enum SanitizedPayload {
    case singleString(String)
    case listString([String])
    case singleNumber(Double)
    case numericRange(start: Double, end: Double)
    case singleBoolean(Bool)
    case singleDate(Date)
    case dateRange(start: Date, end: Date)
}

enum SanitizerResolver {
    static func sanitize(_ operation: FronteggOperation, value: [String: Any?]) -> SanitizedPayload? {
        switch operation {
        case .matches: return sanitizeSingleString(value)
        case .contains, .startsWith, .endsWith, .inList: return sanitizeListString(value)
        case .equal, .greaterThan, .greaterThanEqual, .lesserThan, .lesserThanEqual:
            return sanitizeSingleNumber(value)
        case .betweenNumeric: return sanitizeNumericRange(value)
        case .is: return sanitizeSingleBoolean(value)
        case .on, .onOrAfter, .onOrBefore: return sanitizeSingleDate(value)
        case .betweenDate: return sanitizeDateRange(value)
        }
    }

    private static func sanitizeSingleString(_ v: [String: Any?]) -> SanitizedPayload? {
        guard let s = v["string"] as? String else { return nil }
        return .singleString(s)
    }

    private static func sanitizeListString(_ v: [String: Any?]) -> SanitizedPayload? {
        guard let raw = v["list"] as? [Any?] else { return nil }
        var out: [String] = []
        for item in raw {
            guard let s = item as? String else { return nil }
            out.append(s)
        }
        return .listString(out)
    }

    private static func sanitizeSingleNumber(_ v: [String: Any?]) -> SanitizedPayload? {
        guard let n = coerceNumber(v["number"] ?? nil) else { return nil }
        return .singleNumber(n)
    }

    private static func sanitizeNumericRange(_ v: [String: Any?]) -> SanitizedPayload? {
        guard let s = coerceNumber(v["start"] ?? nil),
              let e = coerceNumber(v["end"] ?? nil) else { return nil }
        return .numericRange(start: s, end: e)
    }

    private static func sanitizeSingleBoolean(_ v: [String: Any?]) -> SanitizedPayload? {
        guard let b = v["boolean"] as? Bool else { return nil }
        return .singleBoolean(b)
    }

    private static func sanitizeSingleDate(_ v: [String: Any?]) -> SanitizedPayload? {
        guard let d = coerceDate(v["date"] ?? nil) else { return nil }
        return .singleDate(d)
    }

    private static func sanitizeDateRange(_ v: [String: Any?]) -> SanitizedPayload? {
        guard let s = coerceDate(v["start"] ?? nil),
              let e = coerceDate(v["end"] ?? nil) else { return nil }
        return .dateRange(start: s, end: e)
    }
}

/// Type coercion helpers used by both `SanitizerResolver` (to parse condition
/// payloads) and `OperationResolver` (to coerce attribute values pulled from the
/// JWT/custom map).
///
/// Mirror web's strictness as closely as we can — `Bool` is intentionally NOT
/// coerced into a number (Swift bridges `Bool` through `NSNumber`, which lets it
/// pass an `as? Double` cast — guard against that explicitly).
func coerceNumber(_ value: Any?) -> Double? {
    if value is Bool { return nil }
    if let d = value as? Double { return d }
    if let i = value as? Int { return Double(i) }
    if let i = value as? Int64 { return Double(i) }
    if let f = value as? Float { return Double(f) }
    if let n = value as? NSNumber {
        // NSNumber bridges everything including Bool — re-check to defend against
        // a Bool that snuck through the `is Bool` guard above (e.g., from an array).
        if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
        return n.doubleValue
    }
    return nil
}

private let isoFormatters: [DateFormatter] = {
    let patterns = [
        "yyyy-MM-dd'T'HH:mm:ss.SSSXXX",
        "yyyy-MM-dd'T'HH:mm:ssXXX",
        "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
        "yyyy-MM-dd'T'HH:mm:ss'Z'",
        "yyyy-MM-dd"
    ]
    return patterns.map { pattern in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = pattern
        return f
    }
}()

func coerceDate(_ value: Any?) -> Date? {
    if let d = value as? Date { return d }
    if let n = coerceNumber(value) { return Date(timeIntervalSince1970: n / 1000) }
    if let s = value as? String {
        for fmt in isoFormatters {
            if let d = fmt.date(from: s) { return d }
        }
    }
    return nil
}

enum OperationResolver {
    /// Returns a handler `(Any?) -> Bool` for the given (operation, payload). Returns
    /// `nil` when the pair is mismatched — treated as "condition is false" by
    /// `ConditionEvaluator`.
    static func resolve(_ operation: FronteggOperation, payload: SanitizedPayload) -> ((Any?) -> Bool)? {
        switch operation {
        case .startsWith:
            guard case .listString(let list) = payload else { return nil }
            return { attr in (attr as? String).map { a in list.contains(where: { a.hasPrefix($0) }) } ?? false }

        case .endsWith:
            guard case .listString(let list) = payload else { return nil }
            return { attr in (attr as? String).map { a in list.contains(where: { a.hasSuffix($0) }) } ?? false }

        case .contains:
            guard case .listString(let list) = payload else { return nil }
            return { attr in (attr as? String).map { a in list.contains(where: { a.contains($0) }) } ?? false }

        case .inList:
            guard case .listString(let list) = payload else { return nil }
            return { attr in (attr as? String).map { list.contains($0) } ?? false }

        case .matches:
            guard case .singleString(let s) = payload else { return nil }
            guard let regex = try? NSRegularExpression(pattern: s, options: []) else { return { _ in false } }
            return { attr in
                guard let str = attr as? String else { return false }
                let range = NSRange(str.startIndex..<str.endIndex, in: str)
                return regex.firstMatch(in: str, options: [], range: range) != nil
            }

        case .equal: return numericPredicate(payload) { a, n in a == n }
        case .greaterThan: return numericPredicate(payload) { a, n in a > n }
        case .greaterThanEqual: return numericPredicate(payload) { a, n in a >= n }
        case .lesserThan: return numericPredicate(payload) { a, n in a < n }
        case .lesserThanEqual: return numericPredicate(payload) { a, n in a <= n }
        case .betweenNumeric:
            guard case .numericRange(let s, let e) = payload else { return nil }
            return { attr in coerceNumber(attr).map { $0 >= s && $0 <= e } ?? false }

        case .is:
            guard case .singleBoolean(let b) = payload else { return nil }
            return { attr in (attr as? Bool) == b }

        case .on: return datePredicate(payload) { a, d in a.timeIntervalSince1970 == d.timeIntervalSince1970 }
        case .onOrAfter: return datePredicate(payload) { a, d in a.timeIntervalSince1970 >= d.timeIntervalSince1970 }
        case .onOrBefore: return datePredicate(payload) { a, d in a.timeIntervalSince1970 <= d.timeIntervalSince1970 }
        case .betweenDate:
            guard case .dateRange(let s, let e) = payload else { return nil }
            return { attr in
                coerceDate(attr).map { $0.timeIntervalSince1970 >= s.timeIntervalSince1970 && $0.timeIntervalSince1970 <= e.timeIntervalSince1970 } ?? false
            }
        }
    }

    private static func numericPredicate(_ payload: SanitizedPayload, _ compare: @escaping (Double, Double) -> Bool) -> ((Any?) -> Bool)? {
        guard case .singleNumber(let n) = payload else { return nil }
        return { attr in coerceNumber(attr).map { compare($0, n) } ?? false }
    }

    private static func datePredicate(_ payload: SanitizedPayload, _ compare: @escaping (Date, Date) -> Bool) -> ((Any?) -> Bool)? {
        guard case .singleDate(let d) = payload else { return nil }
        return { attr in coerceDate(attr).map { compare($0, d) } ?? false }
    }
}
