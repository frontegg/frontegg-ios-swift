//
//  UserRole.swift
//
//
//  Created by David Frontegg on 22/12/2022.
//


public struct UserRole: Codable, Equatable {
    public var id: String
    public var key: String
    public var isDefault: Bool
    public var name: String
    public var description: String?
    public var permissions: [String]
    public var tenantId: String?
    public var vendorId: String
    public var createdAt: String
    public var updatedAt: String
    
    public static func == (lhs: UserRole, rhs: UserRole) -> Bool {
        return lhs.id == rhs.id &&
               lhs.key == rhs.key &&
               lhs.isDefault == rhs.isDefault &&
               lhs.name == rhs.name &&
               lhs.description == rhs.description &&
               lhs.permissions == rhs.permissions &&
               lhs.tenantId == rhs.tenantId &&
               lhs.vendorId == rhs.vendorId &&
               lhs.createdAt == rhs.createdAt &&
               lhs.updatedAt == rhs.updatedAt
    }
}
