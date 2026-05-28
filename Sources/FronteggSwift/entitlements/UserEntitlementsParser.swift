//
//  UserEntitlementsParser.swift
//  FronteggSwift
//
//  Lenient parser for the `/frontegg/entitlements/api/v2/user-entitlements` JSON
//  response. Mirrors the shape consumed by
//  @frontegg/entitlements-javascript-commons.
//
//  Lenient on purpose — the SDK ships ahead of server-side schema changes. Unknown
//  keys are ignored; malformed sub-objects cause that sub-object to be dropped
//  rather than failing the whole parse.
//

import Foundation

enum UserEntitlementsParser {

    static func parse(_ json: [String: Any]) -> UserEntitlementsContext {
        let features = parseFeatures(json["features"] as? [String: Any])
        let plans = parsePlans(json["plans"] as? [String: Any])
        let permissions = parsePermissions(json["permissions"] as? [String: Any])
        return UserEntitlementsContext(features: features, plans: plans, permissions: permissions)
    }

    private static func parseFeatures(_ node: [String: Any]?) -> [String: FeatureDetail] {
        guard let node = node else { return [:] }
        var out: [String: FeatureDetail] = [:]
        for (key, value) in node {
            guard let obj = value as? [String: Any] else { continue }
            let planIds = (obj["planIds"] as? [Any]).flatMap { asStringList($0) } ?? []
            let expireTime = asNullableInt64(obj["expireTime"])
            let linkedPermissions = (obj["linkedPermissions"] as? [Any]).flatMap { asStringList($0) } ?? []
            let featureFlag = parseFeatureFlag(obj["featureFlag"] as? [String: Any])
            out[key] = FeatureDetail(
                planIds: planIds,
                expireTime: expireTime,
                linkedPermissions: linkedPermissions,
                featureFlag: featureFlag
            )
        }
        return out
    }

    private static func parsePlans(_ node: [String: Any]?) -> [String: Plan] {
        guard let node = node else { return [:] }
        var out: [String: Plan] = [:]
        for (key, value) in node {
            guard let obj = value as? [String: Any] else { continue }
            // `defaultTreatment` is required for a plan to be meaningful; drop the
            // plan entirely if it's missing rather than guessing.
            guard let treatmentRaw = obj["defaultTreatment"] as? String,
                  let defaultTreatment = Treatment(rawValue: treatmentRaw) else { continue }
            let rules = parseRules(obj["rules"] as? [Any])
            out[key] = Plan(defaultTreatment: defaultTreatment, rules: rules)
        }
        return out
    }

    private static func parsePermissions(_ node: [String: Any]?) -> [String: Bool] {
        guard let node = node else { return [:] }
        var out: [String: Bool] = [:]
        for (key, value) in node {
            // JSONSerialization gives Bool through NSNumber; filter to actual Bool.
            if let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() {
                out[key] = n.boolValue
            }
        }
        return out
    }

    private static func parseFeatureFlag(_ node: [String: Any]?) -> FeatureFlag? {
        guard let node = node else { return nil }
        guard let on = (node["on"] as? NSNumber).flatMap({ n in CFGetTypeID(n) == CFBooleanGetTypeID() ? n.boolValue : nil }),
              let offTreatmentRaw = node["offTreatment"] as? String,
              let offTreatment = Treatment(rawValue: offTreatmentRaw),
              let defaultTreatmentRaw = node["defaultTreatment"] as? String,
              let defaultTreatment = Treatment(rawValue: defaultTreatmentRaw) else { return nil }
        let rules = parseRules(node["rules"] as? [Any])
        return FeatureFlag(
            on: on,
            offTreatment: offTreatment,
            defaultTreatment: defaultTreatment,
            rules: rules
        )
    }

    private static func parseRules(_ node: [Any]?) -> [Rule]? {
        guard let node = node else { return nil }
        var out: [Rule] = []
        for element in node {
            guard let obj = element as? [String: Any],
                  let rule = parseRule(obj) else { continue }
            out.append(rule)
        }
        return out
    }

    private static func parseRule(_ obj: [String: Any]) -> Rule? {
        guard let logicRaw = obj["conditionLogic"] as? String,
              let logic = ConditionLogic(rawValue: logicRaw),
              let treatmentRaw = obj["treatment"] as? String,
              let treatment = Treatment(rawValue: treatmentRaw),
              let conditionsNode = obj["conditions"] as? [Any] else { return nil }
        var conditions: [Condition] = []
        for c in conditionsNode {
            guard let cObj = c as? [String: Any],
                  let condition = parseCondition(cObj) else { continue }
            conditions.append(condition)
        }
        if conditions.isEmpty { return nil }
        return Rule(conditionLogic: logic, conditions: conditions, treatment: treatment)
    }

    private static func parseCondition(_ obj: [String: Any]) -> Condition? {
        guard let attribute = obj["attribute"] as? String,
              let opRaw = obj["op"] as? String,
              let op = FronteggOperation(rawValue: opRaw),
              let valueNode = obj["value"] as? [String: Any] else { return nil }
        let negate = (obj["negate"] as? Bool) ?? false
        return Condition(attribute: attribute, negate: negate, op: op, value: valueNode)
    }

    private static func asStringList(_ raw: [Any]) -> [String] {
        var out: [String] = []
        for e in raw {
            guard let s = e as? String else { continue }
            out.append(s)
        }
        return out
    }

    private static func asNullableInt64(_ value: Any?) -> Int64? {
        guard let value = value, !(value is NSNull) else { return nil }
        if let i = value as? Int { return Int64(i) }
        if let i = value as? Int64 { return i }
        if let i = value as? Int32 { return Int64(i) }
        if let d = value as? Double { return Int64(d) }
        if let n = value as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            return n.int64Value
        }
        return nil
    }
}
