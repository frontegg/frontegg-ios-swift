//
//  Entitlements.swift
//  FronteggSwift
//

import Foundation

private struct UserEntitlementsResponse: Decodable {
    let features: [String: FeatureDetail]?
    let permissions: [String: Bool]?

    struct FeatureDetail: Decodable {}
}

public struct EntitlementState {
    public let featureKeys: Set<String>
    public let permissionKeys: Set<String>

    public static let empty = EntitlementState(featureKeys: [], permissionKeys: [])
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

    public var state: EntitlementState {
        q.sync { _state }
    }

    private func setState(_ new: EntitlementState) {
        q.sync(flags: .barrier) { _state = new }
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
            let parsed = try JSONDecoder().decode(UserEntitlementsResponse.self, from: data)

            var featureKeys = Set<String>()
            var permissionKeys = Set<String>()

            if let features = parsed.features {
                featureKeys.formUnion(features.keys)
            }
            if let permissions = parsed.permissions {
                permissionKeys.formUnion(permissions.filter { $0.value }.map(\.key))
            }

            setState(EntitlementState(featureKeys: featureKeys, permissionKeys: permissionKeys))
            logger.info("Loaded entitlements: \(featureKeys.count) feature(s), \(permissionKeys.count) permission(s)")
            return true
        } catch {
            logger.warning("Failed to load user entitlements: \(error)")
            return false
        }
    }

    public func clear() {
        setState(.empty)
    }

    public func checkFeature(featureKey: String) -> Entitlement {
        guard enabled else {
            return Entitlement(isEntitled: false, justification: "ENTITLEMENTS_DISABLED")
        }
        let entitled = state.featureKeys.contains(featureKey)
        return Entitlement(isEntitled: entitled, justification: entitled ? nil : "MISSING_FEATURE")
    }

    public func checkPermission(permissionKey: String) -> Entitlement {
        guard enabled else {
            return Entitlement(isEntitled: false, justification: "ENTITLEMENTS_DISABLED")
        }
        let entitled = state.permissionKeys.contains(permissionKey)
        return Entitlement(isEntitled: entitled, justification: entitled ? nil : "MISSING_PERMISSION")
    }
}
