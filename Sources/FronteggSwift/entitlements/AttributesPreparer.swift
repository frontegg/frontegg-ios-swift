//
//  AttributesPreparer.swift
//  FronteggSwift
//
//  Port of `prepareAttributes` from @frontegg/entitlements-javascript-commons.
//

import Foundation

enum AttributesPreparer {

    static let fronteggPrefix = "frontegg."
    static let jwtPrefix = "jwt."

    /// Merges three sources into the rule-evaluation attribute bag:
    ///   1. Custom attributes provided by the host app, used as-is (e.g.
    ///      `"customAttr"`).
    ///   2. Frontegg-derived attributes (`email`, `emailVerified`, `tenantId`,
    ///      `userId`) pulled out of the JWT claims and prefixed `frontegg.`.
    ///   3. The full flattened JWT claim tree, prefixed `jwt.` — so a nested
    ///      `{"metadata": {"plan": "pro"}}` claim becomes `jwt.metadata.plan`.
    static func prepare(_ attributes: Attributes) -> [String: Any?] {
        var merged: [String: Any?] = [:]
        if let custom = attributes.custom {
            for (k, v) in custom { merged[k] = v }
        }
        let jwt = attributes.jwt ?? [:]
        let flatJwt = flatten(jwt)
        for (k, v) in defaultFronteggAttributes(jwt) {
            merged[fronteggPrefix + k] = v
        }
        for (k, v) in flatJwt {
            merged[jwtPrefix + k] = v
        }
        return merged
    }

    /// Frontegg-canonical fields derived from JWT claims, exactly mirroring web's
    /// `defaultFronteggAttributesMapper`.
    ///
    ///   `jwt.id` (or `sub`) → `frontegg.userId`
    ///   `jwt.email`, `jwt.email_verified`, `jwt.tenantId` → corresponding camelCase
    private static func defaultFronteggAttributes(_ jwt: [String: Any?]) -> [String: Any?] {
        var out: [String: Any?] = [:]
        out["email"] = jwt["email"] ?? nil
        out["emailVerified"] = jwt["email_verified"] ?? nil
        out["tenantId"] = jwt["tenantId"] ?? nil
        // Web maps from `jwt.id`; mobile typically has `sub` instead. Fall through.
        out["userId"] = jwt["id"] ?? jwt["sub"] ?? nil
        return out
    }

    /// Depth-first flattening with `.`-joined keys. List values are kept as-is —
    /// they're matched element-wise by operations like `in_list`/`contains` against
    /// the attribute payload's `list` field, not by attribute path. Matches web.
    static func flatten(_ input: [String: Any?], prefix: String = "") -> [String: Any?] {
        var out: [String: Any?] = [:]
        for (k, v) in input {
            let key = prefix.isEmpty ? k : "\(prefix).\(k)"
            if let nested = v as? [String: Any?] {
                for (nk, nv) in flatten(nested, prefix: key) {
                    out[nk] = nv
                }
            } else if let nested = v as? [String: Any] {
                // JSONSerialization gives us `[String: Any]`, not `[String: Any?]`.
                let normalized = nested.mapValues { $0 as Any? }
                for (nk, nv) in flatten(normalized, prefix: key) {
                    out[nk] = nv
                }
            } else {
                out[key] = v
            }
        }
        return out
    }
}
