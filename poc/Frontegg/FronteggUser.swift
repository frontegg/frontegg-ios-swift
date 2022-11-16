//
//  FronteggUser.swift
//  poc
//
//  Created by David Frontegg on 14/11/2022.
//

import Foundation


struct FronteggRole: Codable {
    var id: String
    var key: String
    var isDefault: Bool
    var name: String
    var description: String?
    var permissions: [String]
    var tenantId: String?
    var vendorId: String
    var createdAt: Date
    var updatedAt: Date
}

struct FronteggRolePermission: Codable {
    var id: String
    var key: String
    var name: String
    var description: String?
    var categoryId: String
    var fePermission: Bool
    var createdAt: Date
    var updatedAt: Date
}

struct FronteggUser {
    
    enum DecodeError: Error {
        case invalidJsonData
    }
    
    var id: String
    var email: String
//    var mfaEnrolled: Bool
    var name: String
    var profilePictureUrl:String
//    var phoneNumber: String?
//    var profileImage: String?
//    var profilePictureUrl: String
//    var roles: [FronteggRole];
//    var permissions: [FronteggRolePermission];
//    var tenantId: String
//    var tenantIds: [String];
//    var activatedForTenant: Bool?
//    var metadata: Any?
//    var roleIds: [String]
//    var verified: Bool?
//    var superUser: Bool?
    
    
}

extension FronteggUser: Codable {
    init(dictionary: [String: Any]) throws {
        self = try JSONDecoder().decode(FronteggUser.self, from: JSONSerialization.data(withJSONObject: dictionary))
    }
    private enum CodingKeys: String, CodingKey {
        case id = "sub",
             name = "name",
             email = "email",
             profilePictureUrl = "profilePictureUrl"
    }
}
