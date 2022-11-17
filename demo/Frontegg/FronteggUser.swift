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

struct FronteggUser: Codable {
    
    enum DecodeError: Error {
        case invalidJsonData
    }
    
    var id: String
    var email: String
    var mfaEnrolled: Bool
    var name: String
    var profilePictureUrl: String
    var phoneNumber: String?
    var profileImage: String?
    var roles: [FronteggRole]
    var permissions: [FronteggRolePermission]
    var tenantId: String
    var tenantIds: [String]
    var activatedForTenant: Bool
    var metadata: String?
    var roleIds: [String]
    var verified: Bool
    var superUser: Bool

    //    init(dictionary: [String: Any]) throws {
    //        self =
    //    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.id = try container.decode(String.self, forKey: .id)
        self.email = try container.decode(String.self, forKey: .email)
        self.mfaEnrolled = (try? container.decodeIfPresent(Bool.self, forKey: .mfaEnrolled)) ?? false
        self.name = try container.decode(String.self, forKey: .name)
        self.profilePictureUrl = try container.decode(String.self, forKey: .profilePictureUrl)
        self.phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber)
        self.profileImage = try container.decodeIfPresent(String.self, forKey: .profileImage)
        self.roles = try container.decode([FronteggRole].self, forKey: .roles)
        self.permissions = try container.decode([FronteggRolePermission].self, forKey: .permissions)
        self.tenantId = try container.decode(String.self, forKey: .tenantId)
        self.tenantIds = try container.decode([String].self, forKey: .tenantIds)
        self.activatedForTenant = (try? container.decodeIfPresent(Bool.self, forKey: .activatedForTenant)) ?? false
        self.metadata = try container.decodeIfPresent(String.self, forKey: .metadata)
        self.roleIds = try container.decode([String].self, forKey: .roleIds)
        self.verified = (try? container.decodeIfPresent(Bool.self, forKey: .verified)) ?? false
        self.superUser = (try? container.decodeIfPresent(Bool.self, forKey: .superUser)) ?? false
    }
    
    init(dictionary: [String: Any]) throws {
        self = try JSONDecoder().decode(FronteggUser.self, from: JSONSerialization.data(withJSONObject: dictionary))
    }

}

//extension FronteggUser: Codable {

//    private enum CodingKeys: String, CodingKey {
//        case id = "sub",
//             name = "name",
//             email = "email",
//             profilePictureUrl = "profilePictureUrl"
//    }
//}
