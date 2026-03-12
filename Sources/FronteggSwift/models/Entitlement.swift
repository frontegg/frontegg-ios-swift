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
