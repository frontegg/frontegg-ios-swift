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
}
