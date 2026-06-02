//
//  Evaluators.swift
//  FronteggSwift
//
//  Port of the condition / rule / plan / featureFlag / feature / permission
//  evaluator chain from @frontegg/entitlements-javascript-commons.
//

import Foundation

enum ConditionEvaluator {
    /// Mirrors `createConditionEvaluator` from web. A condition is true iff the
    /// value sanitizes, the attribute exists in the prepared map, the operation
    /// handler returns true. `negate` inverts the final result — but only when
    /// sanitization/handler succeed; an absent attribute is unconditionally false
    /// (matches web's `attributes[key] !== undefined` precheck before negate).
    static func evaluate(_ condition: Condition, attributes: [String: Any?]) -> Bool {
        guard let payload = SanitizerResolver.sanitize(condition.op, value: condition.rawValue()),
              let handler = OperationResolver.resolve(condition.op, payload: payload) else {
            return false
        }
        guard attributes.keys.contains(condition.attribute) else { return false }
        let value = attributes[condition.attribute] ?? nil
        guard value != nil else { return false }
        let raw = handler(value)
        return condition.negate ? !raw : raw
    }
}

enum RuleEvaluationResult {
    case treatable
    case insufficient
}

enum RuleEvaluator {
    /// A rule is `treatable` iff every condition evaluates true (web only ships
    /// `ConditionLogicEnum.And`; if the server ever introduces other operators, the
    /// `ConditionLogic` enum is the place to extend).
    static func evaluate(_ rule: Rule, attributes: [String: Any?]) -> RuleEvaluationResult {
        let all = rule.conditions.allSatisfy { ConditionEvaluator.evaluate($0, attributes: attributes) }
        return all ? .treatable : .insufficient
    }
}

enum PlanEvaluator {
    /// Rules are checked in document order. The first rule whose conditions all
    /// match produces the plan's treatment; if no rule matches, the plan falls
    /// back to `defaultTreatment`. This is the layer that turns
    /// `defaultTreatment: "false"` into "not entitled to SSO" on web in FR-24821.
    static func evaluate(_ plan: Plan, attributes: [String: Any?]) -> Treatment {
        if let matching = (plan.rules ?? []).first(where: {
            RuleEvaluator.evaluate($0, attributes: attributes) == .treatable
        }) {
            return matching.treatment
        }
        return plan.defaultTreatment
    }
}

enum FeatureFlagEvaluator {
    ///   * flag off  → `offTreatment`
    ///   * flag on   → first matching rule's treatment, else `defaultTreatment`
    static func evaluate(_ flag: FeatureFlag, attributes: [String: Any?]) -> Treatment {
        guard flag.on else { return flag.offTreatment }
        if let matching = (flag.rules ?? []).first(where: {
            RuleEvaluator.evaluate($0, attributes: attributes) == .treatable
        }) {
            return matching.treatment
        }
        return flag.defaultTreatment
    }
}

enum IsEntitledToFeature {
    /// Port of `evaluateIsEntitledToFeature`. Three-evaluator chain with the same
    /// priorities as web:
    ///   1. `directEntitlementEvaluator` — `expireTime != nil`, not expired
    ///   2. `featureFlagEvaluator`        — feature-flag on/off + rules
    ///   3. `planTargetingRulesEvaluator` — for each linked plan, rules then default
    ///
    /// First evaluator returning `isEntitled = true` wins. Otherwise
    /// `BUNDLE_EXPIRED` if any evaluator reported it, else `MISSING_FEATURE`.
    static func evaluate(
        _ featureKey: String,
        context: UserEntitlementsContext?,
        attributes: Attributes = Attributes()
    ) -> EntitlementResult {
        guard let context = context else {
            return EntitlementResult(isEntitled: false, justification: NotEntitledJustification.MISSING_FEATURE)
        }
        let prepared = AttributesPreparer.prepare(attributes)
        var results: [EntitlementResult] = []
        for evaluator in featureEvaluators {
            results.append(evaluator(featureKey, context, prepared))
            if !shouldContinue(results) { break }
        }
        return aggregate(results)
    }

    private static let featureEvaluators: [(String, UserEntitlementsContext, [String: Any?]) -> EntitlementResult] = [
        directEntitlementEvaluator,
        featureFlagEvaluator,
        planTargetingRulesEvaluator
    ]

    /// Mirrors `direct-entitlement.evaluator.ts`.
    ///   * `expireTime` nil  → feature is not directly assigned → `MISSING_FEATURE`
    ///   * `expireTime` = -1 → permanently assigned → entitled
    ///   * `expireTime` > now → assigned, not yet expired → entitled
    ///   * `expireTime` < now → bundle expired → `BUNDLE_EXPIRED`
    static func directEntitlementEvaluator(
        _ featureKey: String,
        _ context: UserEntitlementsContext,
        _ attributes: [String: Any?]
    ) -> EntitlementResult {
        if let feature = context.features[featureKey], let expireTime = feature.expireTime {
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let expired = expireTime != FeatureDetail.NO_EXPIRATION_TIME && expireTime < nowMs
            if !expired { return EntitlementResult(isEntitled: true) }
            return EntitlementResult(isEntitled: false, justification: NotEntitledJustification.BUNDLE_EXPIRED)
        }
        return EntitlementResult(isEntitled: false, justification: NotEntitledJustification.MISSING_FEATURE)
    }

    static func featureFlagEvaluator(
        _ featureKey: String,
        _ context: UserEntitlementsContext,
        _ attributes: [String: Any?]
    ) -> EntitlementResult {
        guard let feature = context.features[featureKey], let flag = feature.featureFlag else {
            return missingFeature()
        }
        let treatment = FeatureFlagEvaluator.evaluate(flag, attributes: attributes)
        return treatment == .true ? EntitlementResult(isEntitled: true) : missingFeature()
    }

    static func planTargetingRulesEvaluator(
        _ featureKey: String,
        _ context: UserEntitlementsContext,
        _ attributes: [String: Any?]
    ) -> EntitlementResult {
        guard let feature = context.features[featureKey], !feature.planIds.isEmpty else {
            return missingFeature()
        }
        for planId in feature.planIds {
            guard let plan = context.plans[planId] else { continue }
            let treatment = PlanEvaluator.evaluate(plan, attributes: attributes)
            if treatment == .true { return EntitlementResult(isEntitled: true) }
        }
        return missingFeature()
    }

    private static func missingFeature() -> EntitlementResult {
        EntitlementResult(isEntitled: false, justification: NotEntitledJustification.MISSING_FEATURE)
    }

    /// Mirrors `getResult` from `entitlement-results.utils.ts`. First
    /// `isEntitled=true` wins; otherwise `BUNDLE_EXPIRED` outranks
    /// `MISSING_FEATURE` so the host app sees a more actionable justification.
    static func aggregate(_ results: [EntitlementResult]) -> EntitlementResult {
        var anyExpired = false
        for r in results {
            if r.isEntitled { return r }
            if r.justification == NotEntitledJustification.BUNDLE_EXPIRED { anyExpired = true }
        }
        return EntitlementResult(
            isEntitled: false,
            justification: anyExpired ? NotEntitledJustification.BUNDLE_EXPIRED : NotEntitledJustification.MISSING_FEATURE
        )
    }

    /// Mirrors `shouldContinue` — stop the chain as soon as any evaluator says yes.
    static func shouldContinue(_ results: [EntitlementResult]) -> Bool {
        results.allSatisfy { !$0.isEntitled }
    }
}

enum IsEntitledToPermission {
    /// Port of `evaluateIsEntitledToPermissions`. Two-step check:
    ///   1. Wildcard-match the permission key against the granted permissions.
    ///   2. If the permission isn't linked to any feature, the wildcard match is
    ///      the whole answer. Otherwise re-run the feature evaluator chain for
    ///      every linked feature; if any feature is entitled, the permission is
    ///      entitled too.
    static func evaluate(
        _ permissionKey: String,
        context: UserEntitlementsContext?,
        attributes: Attributes = Attributes()
    ) -> EntitlementResult {
        guard let context = context else {
            return EntitlementResult(isEntitled: false, justification: NotEntitledJustification.MISSING_PERMISSION)
        }
        guard PermissionMatcher.hasPermission(context.permissions, required: permissionKey) else {
            return EntitlementResult(isEntitled: false, justification: NotEntitledJustification.MISSING_PERMISSION)
        }
        let linkedFeatures = context.features.filter { _, detail in
            detail.linkedPermissions.contains(permissionKey)
        }.map { $0.key }

        if linkedFeatures.isEmpty { return EntitlementResult(isEntitled: true) }

        var results: [EntitlementResult] = []
        for featureKey in linkedFeatures {
            results.append(IsEntitledToFeature.evaluate(featureKey, context: context, attributes: attributes))
            if !IsEntitledToFeature.shouldContinue(results) { break }
        }
        return IsEntitledToFeature.aggregate(results)
    }
}
