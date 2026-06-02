//
//  Entitlements.swift
//  FronteggSwift
//

import Foundation

public struct EntitlementState: Equatable {
    /// Catalog of feature keys in the most recent `/user-entitlements` response.
    /// Kept for backwards compatibility with host apps that render counts/debug
    /// surfaces. **NOT** the verdict — the verdict goes through `checkFeature` /
    /// `checkPermission`, driven off `context`.
    public let featureKeys: Set<String>
    /// Permission keys with `value = true` in the response. Backwards-compat only;
    /// see `featureKeys` note above.
    public let permissionKeys: Set<String>
    /// Structured form used by the evaluators. `nil` when entitlements haven't
    /// been loaded yet or the load failed.
    public let context: UserEntitlementsContext?

    public init(
        featureKeys: Set<String>,
        permissionKeys: Set<String>,
        context: UserEntitlementsContext? = nil
    ) {
        self.featureKeys = featureKeys
        self.permissionKeys = permissionKeys
        self.context = context
    }

    public static let empty = EntitlementState(featureKeys: [], permissionKeys: [], context: nil)
}

public final class Entitlements {
    public struct Config {
        public let api: Api
        public let enabled: Bool
        public init(api: Api, enabled: Bool) {
            self.api = api
            self.enabled = enabled
        }
    }

    private let api: Api
    private let enabled: Bool
    private let logger = getLogger("Entitlements")

    private static let userEntitlementsPath = "frontegg/entitlements/api/v2/user-entitlements"

    private let q = DispatchQueue(label: "entitlements.state", attributes: .concurrent)
    private var _state: EntitlementState = .empty
    private var _hasLoaded: Bool = false

    public var state: EntitlementState {
        q.sync { _state }
    }

    /// True if entitlements have been successfully loaded at least once (even if empty).
    public var hasLoaded: Bool {
        q.sync { _hasLoaded }
    }

    private func setState(_ new: EntitlementState, hasLoaded: Bool = true) {
        q.sync(flags: .barrier) {
            _state = new
            _hasLoaded = hasLoaded
        }
    }

    public init(_ config: Config) {
        self.api = config.api
        self.enabled = config.enabled
    }

    @discardableResult
    public func load(accessToken: String) async -> Bool {
        guard enabled else {
            logger.warning("Entitlements disabled; skipping load")
            return false
        }
        do {
            let (data, response) = try await api.getRequest(
                path: Self.userEntitlementsPath,
                accessToken: accessToken
            )
            guard let http = response as? HTTPURLResponse, http.isSuccess else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                logger.warning("Failed to load user entitlements: HTTP \(code)")
                return false
            }
            // Parse the full UserEntitlementsContext (features w/ planIds /
            // expireTime / linkedPermissions / featureFlag, plans, permissions).
            // Pre-fix the SDK only kept the feature keys + truthy permissions and
            // threw away everything needed to make an actual entitlement decision
            // (FR-24821).
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                logger.warning("Failed to parse user-entitlements response as JSON object")
                return false
            }

            // Diagnostic logging — full RAW response body. Tagged `[ENT-DEBUG]` so
            // it's easy to filter the Xcode console for entitlement diagnostics
            // while triaging FR-24821-style "verdict doesn't match web" reports.
            // The host app's logger is the same instance used for everything else
            // in the SDK; if the host app sets log level below `.info` (or the
            // FronteggApp `logLevel` config is `.debug` / `.info`) this surfaces
            // automatically.
            if let rawString = String(data: data, encoding: .utf8) {
                logger.info("[ENT-DEBUG] RAW /user-entitlements response: \(rawString)")
            }

            let context = UserEntitlementsParser.parse(json)

            // Keep populating featureKeys/permissionKeys for backwards compat with
            // host apps that read them off `auth.entitlements.state` (e.g. the
            // demo's "Cached: N feature(s), M permission(s)" summary).
            // featureKeys is the catalog of feature keys seen in the response.
            // permissionKeys is the set of keys with value=true.
            let featureKeys = Set(context.features.keys)
            let permissionKeys = Set(context.permissions.filter { $0.value }.map { $0.key })

            setState(
                EntitlementState(
                    featureKeys: featureKeys,
                    permissionKeys: permissionKeys,
                    context: context
                )
            )
            logger.info("Loaded entitlements: \(featureKeys.count) feature(s), \(permissionKeys.count) permission(s)")
            logger.info("[ENT-DEBUG] Parsed context — features: \(context.features.count), plans: \(context.plans.count), permissions: \(context.permissions.count)")
            for (key, detail) in context.features {
                let planIdsStr = detail.planIds.isEmpty ? "[]" : "[\(detail.planIds.joined(separator: ","))]"
                let expireStr = detail.expireTime.map { "\($0)" } ?? "nil"
                let flagStr = detail.featureFlag.map { "on=\($0.on) off=\($0.offTreatment.rawValue) default=\($0.defaultTreatment.rawValue) rules=\($0.rules?.count ?? 0)" } ?? "nil"
                logger.info("[ENT-DEBUG]   feature[\(key)]: planIds=\(planIdsStr) expireTime=\(expireStr) featureFlag=\(flagStr) linkedPermissions=\(detail.linkedPermissions)")
            }
            for (key, plan) in context.plans {
                let rulesStr = plan.rules?.count ?? 0
                logger.info("[ENT-DEBUG]   plan[\(key)]: defaultTreatment=\(plan.defaultTreatment.rawValue) rules=\(rulesStr)")
            }
            return true
        } catch {
            logger.warning("Failed to load user entitlements: \(error)")
            return false
        }
    }

    public func clear() {
        setState(.empty, hasLoaded: false)
    }

    /// Evaluates `featureKey` against the cached `UserEntitlementsContext` using
    /// the full decision chain (direct entitlement + feature flag + plan targeting
    /// rules). `attributes` carries JWT claims and any host-app custom attributes
    /// used by rule conditions — see `AttributesPreparer`.
    public func checkFeature(featureKey: String, attributes: Attributes = Attributes()) -> Entitlement {
        guard enabled else {
            return Entitlement(isEntitled: false, justification: NotEntitledJustification.ENTITLEMENTS_DISABLED)
        }
        let result = IsEntitledToFeature.evaluate(featureKey, context: state.context, attributes: attributes)
        logCheckTrace(kind: "feature", key: featureKey, attributes: attributes, result: result)
        return Entitlement(isEntitled: result.isEntitled, justification: result.justification)
    }

    public func checkPermission(permissionKey: String, attributes: Attributes = Attributes()) -> Entitlement {
        guard enabled else {
            return Entitlement(isEntitled: false, justification: NotEntitledJustification.ENTITLEMENTS_DISABLED)
        }
        let result = IsEntitledToPermission.evaluate(permissionKey, context: state.context, attributes: attributes)
        logCheckTrace(kind: "permission", key: permissionKey, attributes: attributes, result: result)
        return Entitlement(isEntitled: result.isEntitled, justification: result.justification)
    }

    /// Diagnostic trace for `getFeatureEntitlements` / `getPermissionEntitlements`.
    /// Shows the prepared attribute bag (so the caller can confirm
    /// `frontegg.tenantId` / `frontegg.email` / etc. actually came through from the
    /// JWT) and the verdict. Tagged `[ENT-DEBUG]` for easy Xcode-console filtering.
    /// Sensitive claims (email, tenantId) only appear in your own test app's
    /// debug log, never leaving the device unless you copy them.
    private func logCheckTrace(kind: String, key: String, attributes: Attributes, result: EntitlementResult) {
        let prepared = AttributesPreparer.prepare(attributes)
        let attributeSummary = prepared
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value ?? "nil")" }
            .joined(separator: ", ")
        let contextStatus: String
        if let ctx = state.context {
            contextStatus = "features=\(ctx.features.count) plans=\(ctx.plans.count) permissions=\(ctx.permissions.count)"
        } else {
            contextStatus = "context=nil"
        }
        logger.info("[ENT-DEBUG] check\(kind)(\"\(key)\") → isEntitled=\(result.isEntitled) justification=\(result.justification ?? "nil")")
        logger.info("[ENT-DEBUG]   context: \(contextStatus)")
        logger.info("[ENT-DEBUG]   attributes: {\(attributeSummary)}")
        // Print the relevant slice of the context for THIS feature/permission so
        // the trace is self-contained — no need to cross-reference the load log.
        if kind == "feature", let ctx = state.context, let feature = ctx.features[key] {
            let planIdsStr = feature.planIds.isEmpty ? "[]" : "[\(feature.planIds.joined(separator: ","))]"
            let expireStr = feature.expireTime.map { "\($0)" } ?? "nil"
            let flagStr = feature.featureFlag.map { "on=\($0.on) off=\($0.offTreatment.rawValue) default=\($0.defaultTreatment.rawValue) rules=\($0.rules?.count ?? 0)" } ?? "nil"
            logger.info("[ENT-DEBUG]   feature slice: planIds=\(planIdsStr) expireTime=\(expireStr) featureFlag=\(flagStr) linkedPermissions=\(feature.linkedPermissions)")
            for planId in feature.planIds {
                if let plan = ctx.plans[planId] {
                    logger.info("[ENT-DEBUG]     linked plan[\(planId)]: defaultTreatment=\(plan.defaultTreatment.rawValue) rules=\(plan.rules?.count ?? 0)")
                } else {
                    logger.info("[ENT-DEBUG]     linked plan[\(planId)]: MISSING from plans map")
                }
            }
        }
    }
}
