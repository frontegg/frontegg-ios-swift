//
//  User.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import Foundation



public struct User: Codable {
    
    enum DecodeError: Error {
        case invalidJsonData
    }
    
    public var id: String
    public var email: String
    public var mfaEnrolled: Bool
    public var name: String
    public var profilePictureUrl: String
    public var phoneNumber: String?
    public var profileImage: String?
    public var roles: [UserRole]
    public var permissions: [UserRolePermission]
    public var tenantId: String
    public var tenantIds: [String]
    public var activatedForTenant: Bool
    public var metadata: String?
    public var verified: Bool
    public var superUser: Bool

    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.id = try container.decode(String.self, forKey: .id)
        self.email = try container.decode(String.self, forKey: .email)
        self.mfaEnrolled = (try? container.decodeIfPresent(Bool.self, forKey: .mfaEnrolled)) ?? false
        self.name = try container.decode(String.self, forKey: .name)
        self.profilePictureUrl = try container.decode(String.self, forKey: .profilePictureUrl)
        self.phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber)
        self.profileImage = try container.decodeIfPresent(String.self, forKey: .profileImage)
        self.roles = try container.decode([UserRole].self, forKey: .roles)
        self.permissions = try container.decode([UserRolePermission].self, forKey: .permissions)
        self.tenantId = try container.decode(String.self, forKey: .tenantId)
        self.tenantIds = try container.decode([String].self, forKey: .tenantIds)
        self.activatedForTenant = (try? container.decodeIfPresent(Bool.self, forKey: .activatedForTenant)) ?? false
        self.metadata = try container.decodeIfPresent(String.self, forKey: .metadata)
//        self.roleIds = try container.decode([String].self, forKey: .roleIds)
        self.verified = (try? container.decodeIfPresent(Bool.self, forKey: .verified)) ?? false
        self.superUser = (try? container.decodeIfPresent(Bool.self, forKey: .superUser)) ?? false
    }
    
    init(dictionary: [String: Any]) throws {
        self = try JSONDecoder().decode(User.self, from: JSONSerialization.data(withJSONObject: dictionary))
    }

}
