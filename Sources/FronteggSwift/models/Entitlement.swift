//
//  Entitlement.swift
//  FronteggSwift
//

import Foundation

public struct Entitlement: Equatable {
    public let isEntitled: Bool
    public let justification: String?

    public init(isEntitled: Bool, justification: String? = nil) {
        self.isEntitled = isEntitled
        self.justification = justification
    }
}

public enum EntitledToOptions {
    case featureKey(String)
    case permissionKey(String)
}

/// Canonical justification codes mirrored from
/// `@frontegg/entitlements-javascript-commons` plus the mobile-specific cases the
/// SDK has historically returned.
///
/// The web SDK exposes `MISSING_FEATURE`, `MISSING_PERMISSION`, and `BUNDLE_EXPIRED`.
/// Mobile additionally needs `NOT_AUTHENTICATED` and `ENTITLEMENTS_DISABLED` to
/// describe SDK-side preconditions that don't exist on web (where the entitlements
/// context is always available synchronously after login).
public enum NotEntitledJustification {
    public static let NOT_AUTHENTICATED = "NOT_AUTHENTICATED"
    public static let ENTITLEMENTS_DISABLED = "ENTITLEMENTS_DISABLED"
    public static let MISSING_FEATURE = "MISSING_FEATURE"
    public static let MISSING_PERMISSION = "MISSING_PERMISSION"
    public static let BUNDLE_EXPIRED = "BUNDLE_EXPIRED"
}
