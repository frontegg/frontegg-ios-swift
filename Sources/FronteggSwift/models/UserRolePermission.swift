//
//  UserRolePermission.swift
//  
//
//  Created by David Frontegg on 22/12/2022.
//

public struct UserRolePermission: Codable, Equatable {
    public var id: String
    public var key: String
    public var name: String
    public var description: String?
    public var categoryId: String
    public var fePermission: Bool
    public var createdAt: String
    public var updatedAt: String
    
    public static func == (lhs: UserRolePermission, rhs: UserRolePermission) -> Bool {
        return lhs.id == rhs.id &&
               lhs.key == rhs.key &&
               lhs.name == rhs.name &&
               lhs.description == rhs.description &&
               lhs.categoryId == rhs.categoryId &&
               lhs.fePermission == rhs.fePermission &&
               lhs.createdAt == rhs.createdAt &&
               lhs.updatedAt == rhs.updatedAt
    }
}
