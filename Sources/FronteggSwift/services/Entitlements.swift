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
        return Entitlement(isEntitled: result.isEntitled, justification: result.justification)
    }

    public func checkPermission(permissionKey: String, attributes: Attributes = Attributes()) -> Entitlement {
        guard enabled else {
            return Entitlement(isEntitled: false, justification: NotEntitledJustification.ENTITLEMENTS_DISABLED)
        }
        let result = IsEntitledToPermission.evaluate(permissionKey, context: state.context, attributes: attributes)
        return Entitlement(isEntitled: result.isEntitled, justification: result.justification)
    }
}
