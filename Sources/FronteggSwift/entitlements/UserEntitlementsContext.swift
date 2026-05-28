//
//  UserEntitlementsContext.swift
//  FronteggSwift
//
//  Port of the UserEntitlementsContext shape from
//  @frontegg/entitlements-javascript-commons (the canonical evaluator the web SDK
//  uses). Mirrors the v2 /frontegg/entitlements/api/v2/user-entitlements response.
//
//  Pre-fix the mobile SDK only kept the `features` map's *keys* and discarded
//  everything else — that's why getFeatureEntitlements(featureKey: "sso") returned
//  isEntitled = true regardless of plan defaultTreatment, expiry, or feature flags.
//  Storing the full structure lets us run the same evaluator chain as web.
//

import Foundation

public struct UserEntitlementsContext: Equatable {
    public let features: [String: FeatureDetail]
    public let plans: [String: Plan]
    public let permissions: [String: Bool]

    public init(features: [String: FeatureDetail], plans: [String: Plan], permissions: [String: Bool]) {
        self.features = features
        self.plans = plans
        self.permissions = permissions
    }
}

public struct FeatureDetail: Equatable {
    public let planIds: [String]
    /// `nil` when this feature is not directly assigned to the user (only reachable
    /// via a plan or feature flag); `NO_EXPIRATION_TIME` when assigned permanently;
    /// otherwise an epoch-millis timestamp.
    public let expireTime: Int64?
    public let linkedPermissions: [String]
    public let featureFlag: FeatureFlag?

    public init(planIds: [String], expireTime: Int64?, linkedPermissions: [String], featureFlag: FeatureFlag?) {
        self.planIds = planIds
        self.expireTime = expireTime
        self.linkedPermissions = linkedPermissions
        self.featureFlag = featureFlag
    }

    /// Sentinel for "directly assigned, never expires". Matches the web SDK's
    /// `NO_EXPIRATION_TIME` constant.
    public static let NO_EXPIRATION_TIME: Int64 = -1
}

public struct Plan: Equatable {
    public let defaultTreatment: Treatment
    public let rules: [Rule]?

    public init(defaultTreatment: Treatment, rules: [Rule]? = nil) {
        self.defaultTreatment = defaultTreatment
        self.rules = rules
    }
}

public struct FeatureFlag: Equatable {
    public let on: Bool
    public let offTreatment: Treatment
    public let defaultTreatment: Treatment
    public let rules: [Rule]?

    public init(on: Bool, offTreatment: Treatment, defaultTreatment: Treatment, rules: [Rule]? = nil) {
        self.on = on
        self.offTreatment = offTreatment
        self.defaultTreatment = defaultTreatment
        self.rules = rules
    }
}

public struct Rule: Equatable {
    public let conditionLogic: ConditionLogic
    public let conditions: [Condition]
    public let treatment: Treatment

    public init(conditionLogic: ConditionLogic, conditions: [Condition], treatment: Treatment) {
        self.conditionLogic = conditionLogic
        self.conditions = conditions
        self.treatment = treatment
    }
}

public enum ConditionLogic: String, Equatable {
    case and
}

public enum Treatment: String, Equatable {
    case `true` = "true"
    case `false` = "false"
}

public struct Condition: Equatable {
    public let attribute: String
    public let negate: Bool
    public let op: FronteggOperation
    /// Raw value shape varies by operation kind (e.g. `["string": "abc"]` for
    /// `matches`, `["list": [...]]` for `in_list`, `["number": 42]` for numeric ops,
    /// `["start": ..., "end": ...]` for ranges, `["boolean": true]` for `is`,
    /// `["date": "..."]` for date ops). The matching sanitizer is responsible for
    /// narrowing to the expected payload.
    public let value: [String: AnyEquatable]

    public init(attribute: String, negate: Bool, op: FronteggOperation, value: [String: Any]) {
        self.attribute = attribute
        self.negate = negate
        self.op = op
        self.value = value.mapValues { AnyEquatable($0) }
    }

    /// Convenience for accessing the underlying raw value as `Any?` for the
    /// sanitizer layer.
    public func rawValue() -> [String: Any?] {
        var out: [String: Any?] = [:]
        for (k, v) in value {
            out[k] = v.value
        }
        return out
    }

    public static func == (lhs: Condition, rhs: Condition) -> Bool {
        lhs.attribute == rhs.attribute &&
            lhs.negate == rhs.negate &&
            lhs.op == rhs.op &&
            lhs.value == rhs.value
    }
}

/// Mirrors `OperationEnum` from `@frontegg/entitlements-javascript-commons`. Raw
/// values match the JSON the server emits.
public enum FronteggOperation: String, Equatable {
    // String
    case inList = "in_list"
    case startsWith = "starts_with"
    case endsWith = "ends_with"
    case contains
    case matches

    // Numeric
    case equal
    case greaterThan = "greater_than"
    case greaterThanEqual = "greater_than_equal"
    case lesserThan = "lower_than"
    case lesserThanEqual = "lower_than_equal"
    case betweenNumeric = "between_numeric"

    // Boolean
    case `is`

    // Date
    case on
    case betweenDate = "between_date"
    case onOrAfter = "on_or_after"
    case onOrBefore = "on_or_before"
}

/// Pair of `isEntitled` flag plus, when negative, a `NotEntitledJustification` code.
public struct EntitlementResult: Equatable {
    public let isEntitled: Bool
    public let justification: String?

    public init(isEntitled: Bool, justification: String? = nil) {
        self.isEntitled = isEntitled
        self.justification = justification
    }
}

public struct Attributes {
    public let custom: [String: Any?]?
    public let jwt: [String: Any?]?

    public init(custom: [String: Any?]? = nil, jwt: [String: Any?]? = nil) {
        self.custom = custom
        self.jwt = jwt
    }
}

/// Type-erased wrapper that lets condition value dictionaries participate in
/// `Equatable` (needed because `[String: Any]` is not `Equatable`). Compares by
/// structural equality of the underlying `Any?`.
public struct AnyEquatable: Equatable {
    public let value: Any?

    public init(_ value: Any?) {
        self.value = value
    }

    public static func == (lhs: AnyEquatable, rhs: AnyEquatable) -> Bool {
        return anyEqual(lhs.value, rhs.value)
    }
}

private func anyEqual(_ a: Any?, _ b: Any?) -> Bool {
    switch (a, b) {
    case (nil, nil): return true
    case let (x as String, y as String): return x == y
    case let (x as Bool, y as Bool): return x == y
    case let (x as Int, y as Int): return x == y
    case let (x as Double, y as Double): return x == y
    case let (x as Date, y as Date): return x == y
    case let (x as [Any?], y as [Any?]):
        guard x.count == y.count else { return false }
        for i in 0..<x.count where !anyEqual(x[i], y[i]) { return false }
        return true
    case let (x as [String: Any?], y as [String: Any?]):
        guard x.keys.sorted() == y.keys.sorted() else { return false }
        for (k, vx) in x where !anyEqual(vx, y[k] ?? nil) { return false }
        return true
    default:
        return false
    }
}
