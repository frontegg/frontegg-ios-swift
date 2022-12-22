//
//  UserRole.swift
//  
//
//  Created by David Frontegg on 22/12/2022.
//


public struct UserRole: Codable {
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
}
