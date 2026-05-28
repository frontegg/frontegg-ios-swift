//
//  EntitlementEvaluatorsTests.swift
//  FronteggSwiftTests
//
//  Port of the Android entitlement evaluator tests. Tests are organized by
//  evaluator layer (condition → rule → plan / featureFlag → feature / permission)
//  with the FR-24821 customer reproduction at the top of the feature suite.
//

import XCTest
@testable import FronteggSwift

final class ConditionEvaluatorTests: XCTestCase {

    private func cond(
        attribute: String,
        op: FronteggOperation,
        value: [String: Any],
        negate: Bool = false
    ) -> Condition {
        Condition(attribute: attribute, negate: negate, op: op, value: value)
    }

    // MARK: - String

    func test_inList_matches() {
        let c = cond(attribute: "frontegg.email", op: .inList, value: ["list": ["a@x.com", "b@x.com"]])
        XCTAssertTrue(ConditionEvaluator.evaluate(c, attributes: ["frontegg.email": "a@x.com"]))
        XCTAssertFalse(ConditionEvaluator.evaluate(c, attributes: ["frontegg.email": "c@x.com"]))
    }

    func test_inList_malformed_payload_returns_false() {
        // `list` element types don't match — sanitizer returns nil → condition false.
        let c = cond(attribute: "k", op: .inList, value: ["list": ["a", 1]])
        XCTAssertFalse(ConditionEvaluator.evaluate(c, attributes: ["k": "a"]))
    }

    func test_startsWith_endsWith_contains() {
        let starts = cond(attribute: "k", op: .startsWith, value: ["list": ["foo", "bar"]])
        XCTAssertTrue(ConditionEvaluator.evaluate(starts, attributes: ["k": "foobar"]))
        XCTAssertTrue(ConditionEvaluator.evaluate(starts, attributes: ["k": "barbaz"]))
        XCTAssertFalse(ConditionEvaluator.evaluate(starts, attributes: ["k": "baz"]))

        let ends = cond(attribute: "k", op: .endsWith, value: ["list": ["xyz"]])
        XCTAssertTrue(ConditionEvaluator.evaluate(ends, attributes: ["k": "abcxyz"]))

        let contains = cond(attribute: "k", op: .contains, value: ["list": ["ll"]])
        XCTAssertTrue(ConditionEvaluator.evaluate(contains, attributes: ["k": "hello"]))
    }

    func test_matches_regex_semantics() {
        let c = cond(attribute: "k", op: .matches, value: ["string": "^foo.*bar$"])
        XCTAssertTrue(ConditionEvaluator.evaluate(c, attributes: ["k": "foo-x-bar"]))
        XCTAssertFalse(ConditionEvaluator.evaluate(c, attributes: ["k": "foo-x-baz"]))
    }

    func test_matches_malformed_regex_returns_false() {
        // Unmatched `(` — NSRegularExpression throws; swallow and return false rather
        // than crash the host app's entitlement check.
        let c = cond(attribute: "k", op: .matches, value: ["string": "("])
        XCTAssertFalse(ConditionEvaluator.evaluate(c, attributes: ["k": "anything"]))
    }

    // MARK: - Numeric

    func test_equal_across_int_and_double() {
        let c = cond(attribute: "k", op: .equal, value: ["number": 42])
        XCTAssertTrue(ConditionEvaluator.evaluate(c, attributes: ["k": 42]))
        XCTAssertTrue(ConditionEvaluator.evaluate(c, attributes: ["k": Int64(42)]))
        XCTAssertTrue(ConditionEvaluator.evaluate(c, attributes: ["k": 42.0]))
        XCTAssertFalse(ConditionEvaluator.evaluate(c, attributes: ["k": 43]))
    }

    func test_betweenNumeric_inclusive() {
        let c = cond(attribute: "k", op: .betweenNumeric, value: ["start": 10, "end": 20])
        XCTAssertTrue(ConditionEvaluator.evaluate(c, attributes: ["k": 10]))
        XCTAssertTrue(ConditionEvaluator.evaluate(c, attributes: ["k": 15]))
        XCTAssertTrue(ConditionEvaluator.evaluate(c, attributes: ["k": 20]))
        XCTAssertFalse(ConditionEvaluator.evaluate(c, attributes: ["k": 21]))
    }

    func test_greaterThan_and_lesserThanEqual() {
        let gt = cond(attribute: "k", op: .greaterThan, value: ["number": 5])
        XCTAssertTrue(ConditionEvaluator.evaluate(gt, attributes: ["k": 6]))
        XCTAssertFalse(ConditionEvaluator.evaluate(gt, attributes: ["k": 5]))
        let lte = cond(attribute: "k", op: .lesserThanEqual, value: ["number": 5])
        XCTAssertTrue(ConditionEvaluator.evaluate(lte, attributes: ["k": 5]))
        XCTAssertFalse(ConditionEvaluator.evaluate(lte, attributes: ["k": 6]))
    }

    // MARK: - Boolean

    func test_boolean_is_strict_rejects_string_true() {
        let c = cond(attribute: "k", op: .is, value: ["boolean": true])
        XCTAssertTrue(ConditionEvaluator.evaluate(c, attributes: ["k": true]))
        XCTAssertFalse(ConditionEvaluator.evaluate(c, attributes: ["k": false]))
        // Web compares with `===`. Match that — string "true" is NOT Bool true.
        XCTAssertFalse(ConditionEvaluator.evaluate(c, attributes: ["k": "true"]))
    }

    // MARK: - Date

    func test_onOrAfter_with_iso_string_attribute() {
        let c = cond(attribute: "k", op: .onOrAfter, value: ["date": "2026-01-01T00:00:00Z"])
        XCTAssertTrue(ConditionEvaluator.evaluate(c, attributes: ["k": "2026-06-01T00:00:00Z"]))
        XCTAssertFalse(ConditionEvaluator.evaluate(c, attributes: ["k": "2025-12-31T00:00:00Z"]))
    }

    func test_betweenDate_inclusive() {
        let c = cond(
            attribute: "k",
            op: .betweenDate,
            value: ["start": "2026-01-01T00:00:00Z", "end": "2026-12-31T00:00:00Z"]
        )
        XCTAssertTrue(ConditionEvaluator.evaluate(c, attributes: ["k": "2026-06-15T00:00:00Z"]))
        XCTAssertFalse(ConditionEvaluator.evaluate(c, attributes: ["k": "2027-01-01T00:00:00Z"]))
    }

    // MARK: - Edge cases

    func test_missing_attribute_is_false_even_with_negate() {
        let c = cond(attribute: "absent", op: .is, value: ["boolean": true], negate: true)
        // Web short-circuits before negate: absent attribute is unconditionally false.
        XCTAssertFalse(ConditionEvaluator.evaluate(c, attributes: ["present": true]))
    }

    func test_negate_inverts_normally_true_match() {
        let c = cond(attribute: "k", op: .is, value: ["boolean": true], negate: true)
        XCTAssertFalse(ConditionEvaluator.evaluate(c, attributes: ["k": true]))
        XCTAssertTrue(ConditionEvaluator.evaluate(c, attributes: ["k": false]))
    }

    func test_type_mismatch_returns_false() {
        // Numeric op expecting a Number, attribute is a String — handler returns false.
        let c = cond(attribute: "k", op: .equal, value: ["number": 5])
        XCTAssertFalse(ConditionEvaluator.evaluate(c, attributes: ["k": "5"]))
    }
}

final class PlanAndFeatureFlagEvaluatorTests: XCTestCase {

    private let ruleMatchingTenantA = Rule(
        conditionLogic: .and,
        conditions: [
            Condition(
                attribute: "frontegg.tenantId",
                negate: false,
                op: .inList,
                value: ["list": ["tenant-A"]]
            )
        ],
        treatment: .true
    )

    func test_plan_defaultTreatment_applies_when_no_rules_match() {
        let plan = Plan(defaultTreatment: .false, rules: [ruleMatchingTenantA])
        XCTAssertEqual(PlanEvaluator.evaluate(plan, attributes: [:]), .false)
        XCTAssertEqual(
            PlanEvaluator.evaluate(plan, attributes: ["frontegg.tenantId": "tenant-B"]),
            .false
        )
    }

    func test_plan_rule_overrides_default_when_conditions_match() {
        let plan = Plan(defaultTreatment: .false, rules: [ruleMatchingTenantA])
        XCTAssertEqual(
            PlanEvaluator.evaluate(plan, attributes: ["frontegg.tenantId": "tenant-A"]),
            .true
        )
    }

    func test_plan_with_no_rules_returns_defaultTreatment() {
        // Exact FR-24821 scenario: defaultTreatment "false", no overriding rules.
        let plan = Plan(defaultTreatment: .false, rules: nil)
        XCTAssertEqual(PlanEvaluator.evaluate(plan, attributes: [:]), .false)
    }

    func test_featureFlag_off_returns_offTreatment_regardless_of_rules() {
        let flag = FeatureFlag(
            on: false,
            offTreatment: .false,
            defaultTreatment: .true,
            rules: [ruleMatchingTenantA]
        )
        XCTAssertEqual(
            FeatureFlagEvaluator.evaluate(flag, attributes: ["frontegg.tenantId": "tenant-A"]),
            .false
        )
    }

    func test_featureFlag_on_uses_rules_then_defaultTreatment() {
        let flag = FeatureFlag(
            on: true,
            offTreatment: .false,
            defaultTreatment: .false,
            rules: [ruleMatchingTenantA]
        )
        XCTAssertEqual(
            FeatureFlagEvaluator.evaluate(flag, attributes: ["frontegg.tenantId": "tenant-A"]),
            .true
        )
        XCTAssertEqual(FeatureFlagEvaluator.evaluate(flag, attributes: [:]), .false)
    }
}

final class IsEntitledToFeatureTests: XCTestCase {

    func test_nil_context_yields_missing_feature() {
        let result = IsEntitledToFeature.evaluate("anything", context: nil)
        XCTAssertFalse(result.isEntitled)
        XCTAssertEqual(result.justification, NotEntitledJustification.MISSING_FEATURE)
    }

    func test_direct_entitlement_with_NO_EXPIRATION_TIME_wins() {
        let ctx = UserEntitlementsContext(
            features: [
                "alpha": FeatureDetail(
                    planIds: [],
                    expireTime: FeatureDetail.NO_EXPIRATION_TIME,
                    linkedPermissions: [],
                    featureFlag: nil
                )
            ],
            plans: [:],
            permissions: [:]
        )
        let result = IsEntitledToFeature.evaluate("alpha", context: ctx)
        XCTAssertTrue(result.isEntitled, "\(result)")
        XCTAssertNil(result.justification)
    }

    func test_direct_entitlement_reports_BUNDLE_EXPIRED_for_past_time() {
        let ctx = UserEntitlementsContext(
            features: [
                "alpha": FeatureDetail(
                    planIds: [],
                    expireTime: 86_400_000, // 1970-01-02 — guaranteed past
                    linkedPermissions: [],
                    featureFlag: nil
                )
            ],
            plans: [:],
            permissions: [:]
        )
        let result = IsEntitledToFeature.evaluate("alpha", context: ctx)
        XCTAssertFalse(result.isEntitled)
        XCTAssertEqual(result.justification, NotEntitledJustification.BUNDLE_EXPIRED)
    }

    func test_featureFlag_on_with_truthy_defaultTreatment_grants_when_direct_does_not() {
        let ctx = UserEntitlementsContext(
            features: [
                "alpha": FeatureDetail(
                    planIds: [],
                    expireTime: nil,
                    linkedPermissions: [],
                    featureFlag: FeatureFlag(on: true, offTreatment: .false, defaultTreatment: .true, rules: nil)
                )
            ],
            plans: [:],
            permissions: [:]
        )
        let result = IsEntitledToFeature.evaluate("alpha", context: ctx)
        XCTAssertTrue(result.isEntitled, "\(result)")
    }

    func test_plan_targeting_evaluator_grants_when_rule_matches_jwt_tenantId() {
        let ctx = UserEntitlementsContext(
            features: [
                "sso": FeatureDetail(
                    planIds: ["plan-1"],
                    expireTime: nil,
                    linkedPermissions: [],
                    featureFlag: nil
                )
            ],
            plans: [
                "plan-1": Plan(
                    defaultTreatment: .false,
                    rules: [
                        Rule(
                            conditionLogic: .and,
                            conditions: [
                                Condition(
                                    attribute: "frontegg.tenantId",
                                    negate: false,
                                    op: .inList,
                                    value: ["list": ["tenant-A"]]
                                )
                            ],
                            treatment: .true
                        )
                    ]
                )
            ],
            permissions: [:]
        )
        let attrs = Attributes(jwt: ["tenantId": "tenant-A"])
        let result = IsEntitledToFeature.evaluate("sso", context: ctx, attributes: attrs)
        XCTAssertTrue(result.isEntitled, "\(result)")
    }

    func test_fr_24821_sso_with_defaultTreatment_false_is_not_entitled() {
        // The exact customer reproduction from FR-24821 / Yonatan's Slack thread:
        //
        // The /user-entitlements response lists "sso" in the features catalog with a
        // linked plan that has `defaultTreatment: "false"` (and no overriding rules
        // for the current tenant). Web evaluates this correctly as "not entitled".
        // Pre-fix the mobile SDK only looked at the features map's keys and reported
        // isEntitled=true — that's the bug this whole PR closes.
        let ctx = UserEntitlementsContext(
            features: [
                "sso": FeatureDetail(
                    planIds: ["ID_1"],
                    expireTime: nil,
                    linkedPermissions: [],
                    featureFlag: nil
                )
            ],
            plans: [
                "ID_1": Plan(defaultTreatment: .false, rules: nil)
            ],
            permissions: [:]
        )
        let attrs = Attributes(jwt: ["tenantId": "tenant-without-sso"])
        let result = IsEntitledToFeature.evaluate("sso", context: ctx, attributes: attrs)
        XCTAssertFalse(result.isEntitled, "\(result)")
        XCTAssertEqual(result.justification, NotEntitledJustification.MISSING_FEATURE)
    }

    func test_aggregate_reports_BUNDLE_EXPIRED_if_any_evaluator_hit_expiry() {
        let ctx = UserEntitlementsContext(
            features: [
                "alpha": FeatureDetail(
                    planIds: [],
                    expireTime: 86_400_000, // expired
                    linkedPermissions: [],
                    featureFlag: nil
                )
            ],
            plans: [:],
            permissions: [:]
        )
        let result = IsEntitledToFeature.evaluate("alpha", context: ctx)
        XCTAssertEqual(result.justification, NotEntitledJustification.BUNDLE_EXPIRED)
    }

    func test_feature_missing_from_catalog_yields_MISSING_FEATURE() {
        let ctx = UserEntitlementsContext(features: [:], plans: [:], permissions: [:])
        let result = IsEntitledToFeature.evaluate("unknown", context: ctx)
        XCTAssertFalse(result.isEntitled)
        XCTAssertEqual(result.justification, NotEntitledJustification.MISSING_FEATURE)
    }
}

final class IsEntitledToPermissionTests: XCTestCase {

    private let emptyCtx = UserEntitlementsContext(features: [:], plans: [:], permissions: [:])

    func test_nil_context_yields_MISSING_PERMISSION() {
        let result = IsEntitledToPermission.evaluate("fe.secure.read.users", context: nil)
        XCTAssertFalse(result.isEntitled)
        XCTAssertEqual(result.justification, NotEntitledJustification.MISSING_PERMISSION)
    }

    func test_wildcard_granted_permission_matches_concrete_request() {
        let ctx = UserEntitlementsContext(
            features: [:], plans: [:], permissions: ["fe.secure.*": true]
        )
        let result = IsEntitledToPermission.evaluate("fe.secure.read.users", context: ctx)
        XCTAssertTrue(result.isEntitled, "\(result)")
    }

    func test_wildcard_dot_is_literal_not_regex_any() {
        // "fe.secure" should NOT match "feXsecure" — dots are escaped.
        let ctx = UserEntitlementsContext(features: [:], plans: [:], permissions: ["fe.secure": true])
        let result = IsEntitledToPermission.evaluate("feXsecure", context: ctx)
        XCTAssertFalse(result.isEntitled, "\(result)")
    }

    func test_permission_with_no_linked_features_is_entitled_once_granted() {
        let ctx = UserEntitlementsContext(
            features: [:], plans: [:], permissions: ["fe.profile.read": true]
        )
        let result = IsEntitledToPermission.evaluate("fe.profile.read", context: ctx)
        XCTAssertTrue(result.isEntitled, "\(result)")
    }

    func test_permission_linked_to_not_entitled_feature_is_denied() {
        // Permission is granted by the server but it's gated on the "sso" feature,
        // which in turn rolls up to a plan with defaultTreatment "false". The
        // permission should NOT be reported as entitled.
        let ctx = UserEntitlementsContext(
            features: [
                "sso": FeatureDetail(
                    planIds: ["plan-no-sso"],
                    expireTime: nil,
                    linkedPermissions: ["fe.secure.read.samlDefaultRoles"],
                    featureFlag: nil
                )
            ],
            plans: [
                "plan-no-sso": Plan(defaultTreatment: .false, rules: nil)
            ],
            permissions: ["fe.secure.read.samlDefaultRoles": true]
        )
        let result = IsEntitledToPermission.evaluate("fe.secure.read.samlDefaultRoles", context: ctx)
        XCTAssertFalse(result.isEntitled, "\(result)")
        XCTAssertEqual(result.justification, NotEntitledJustification.MISSING_FEATURE)
    }

    func test_permission_linked_to_entitled_feature_passes() {
        let ctx = UserEntitlementsContext(
            features: [
                "alpha": FeatureDetail(
                    planIds: [],
                    expireTime: FeatureDetail.NO_EXPIRATION_TIME,
                    linkedPermissions: ["fe.profile.write"],
                    featureFlag: nil
                )
            ],
            plans: [:],
            permissions: ["fe.profile.write": true]
        )
        let result = IsEntitledToPermission.evaluate("fe.profile.write", context: ctx)
        XCTAssertTrue(result.isEntitled, "\(result)")
    }
}

final class UserEntitlementsParserTests: XCTestCase {

    private func parse(_ json: String) -> UserEntitlementsContext {
        let data = json.data(using: .utf8)!
        let obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        return UserEntitlementsParser.parse(obj)
    }

    func test_FR_24821_minimal_response() {
        let json = """
        {
          "features": {
            "sso": { "planIds": ["ID_1"], "expireTime": null, "linkedPermissions": [] }
          },
          "plans": {
            "ID_1": { "defaultTreatment": "false" }
          },
          "permissions": {}
        }
        """
        let ctx = parse(json)
        let sso = ctx.features["sso"]
        XCTAssertNotNil(sso)
        XCTAssertEqual(sso?.planIds, ["ID_1"])
        XCTAssertNil(sso?.expireTime, "expireTime explicitly null must remain nil")

        let plan = ctx.plans["ID_1"]
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.defaultTreatment, .false)
    }

    func test_expireTime_NO_EXPIRATION_TIME_parses() {
        let json = """
        {"features":{"alpha":{"planIds":[],"expireTime":-1,"linkedPermissions":[]}},"plans":{},"permissions":{}}
        """
        let ctx = parse(json)
        XCTAssertEqual(ctx.features["alpha"]?.expireTime, FeatureDetail.NO_EXPIRATION_TIME)
    }

    func test_permissions_drops_non_boolean_entries() {
        let json = """
        {
          "features": {},
          "plans": {},
          "permissions": {
            "fe.read": true,
            "fe.write": false,
            "fe.junk": "not-a-bool"
          }
        }
        """
        let ctx = parse(json)
        XCTAssertEqual(ctx.permissions["fe.read"], true)
        XCTAssertEqual(ctx.permissions["fe.write"], false)
        XCTAssertNil(ctx.permissions["fe.junk"], "non-boolean entry must drop")
    }

    func test_rule_with_unknown_operation_is_dropped() {
        // Forward-compat: server may add operations the SDK doesn't know yet.
        let json = """
        {
          "features": { "alpha": { "planIds": ["p1"], "expireTime": null, "linkedPermissions": [] } },
          "plans": {
            "p1": {
              "defaultTreatment": "false",
              "rules": [
                {
                  "conditionLogic": "and",
                  "treatment": "true",
                  "conditions": [
                    {"attribute":"x","negate":false,"op":"future_op","value":{}}
                  ]
                }
              ]
            }
          },
          "permissions": {}
        }
        """
        let ctx = parse(json)
        XCTAssertEqual(ctx.plans["p1"]?.rules?.count, 0, "rule with unknown op must drop")
    }

    func test_feature_flag_with_rules_parses_end_to_end() {
        let json = """
        {
          "features": {
            "beta": {
              "planIds": [], "expireTime": null, "linkedPermissions": [],
              "featureFlag": {
                "on": true, "offTreatment": "false", "defaultTreatment": "false",
                "rules": [
                  {
                    "conditionLogic": "and", "treatment": "true",
                    "conditions": [
                      {"attribute":"frontegg.tenantId","negate":false,"op":"in_list","value":{"list":["tenant-A"]}}
                    ]
                  }
                ]
              }
            }
          },
          "plans": {},
          "permissions": {}
        }
        """
        let ctx = parse(json)
        let flag = ctx.features["beta"]?.featureFlag
        XCTAssertEqual(flag?.on, true)
        XCTAssertEqual(flag?.offTreatment, .false)
        XCTAssertEqual(flag?.defaultTreatment, .false)
        let rule = flag?.rules?[0]
        XCTAssertEqual(rule?.treatment, .true)
        XCTAssertEqual(rule?.conditions[0].attribute, "frontegg.tenantId")
        XCTAssertEqual(rule?.conditions[0].op, FronteggOperation.inList)
    }

    func test_malformed_feature_flag_drops_flag_keeps_feature() {
        let json = """
        {
          "features": {
            "beta": {
              "planIds": [], "expireTime": null, "linkedPermissions": [],
              "featureFlag": {"on": true}
            }
          },
          "plans": {},
          "permissions": {}
        }
        """
        let ctx = parse(json)
        XCTAssertNotNil(ctx.features["beta"])
        XCTAssertNil(ctx.features["beta"]?.featureFlag, "malformed flag must drop, not crash the feature")
    }
}
