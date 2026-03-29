//
//  User.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import Foundation

public struct User: Codable, Equatable, Sendable {
    
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
    public var tenants: [Tenant]
    public var activeTenant: Tenant
    public var activatedForTenant: Bool
    public var metadata: String?
    public var verified: Bool
    public var superUser: Bool
    
    
    /// Memberwise initializer for constructing User programmatically (e.g., from JWT claims).
    internal init(
        id: String, email: String, mfaEnrolled: Bool, name: String,
        profilePictureUrl: String, phoneNumber: String? = nil, profileImage: String? = nil,
        roles: [UserRole], permissions: [UserRolePermission],
        tenantId: String, tenantIds: [String],
        tenants: [Tenant], activeTenant: Tenant,
        activatedForTenant: Bool, metadata: String? = nil,
        verified: Bool, superUser: Bool
    ) {
        self.id = id
        self.email = email
        self.mfaEnrolled = mfaEnrolled
        self.name = name
        self.profilePictureUrl = profilePictureUrl
        self.phoneNumber = phoneNumber
        self.profileImage = profileImage
        self.roles = roles
        self.permissions = permissions
        self.tenantId = tenantId
        self.tenantIds = tenantIds
        self.tenants = tenants
        self.activeTenant = activeTenant
        self.activatedForTenant = activatedForTenant
        self.metadata = metadata
        self.verified = verified
        self.superUser = superUser
    }

    private static func stringClaim(_ claims: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = claims[key] as? String, !value.isEmpty {
                return value
            }
            if let value = claims[key] as? NSNumber {
                return value.stringValue
            }
        }
        return nil
    }

    private static func stringArrayClaim(_ claims: [String: Any], keys: [String]) -> [String]? {
        for key in keys {
            if let values = claims[key] as? [String], !values.isEmpty {
                return values
            }
            if let values = claims[key] as? [Any] {
                let strings = values.compactMap { value -> String? in
                    guard let string = value as? String, !string.isEmpty else { return nil }
                    return string
                }
                if !strings.isEmpty {
                    return strings
                }
            }
        }
        return nil
    }

    private static func boolClaim(_ claims: [String: Any], keys: [String], default defaultValue: Bool = false) -> Bool {
        for key in keys {
            if let value = claims[key] as? Bool {
                return value
            }
            if let value = claims[key] as? NSNumber {
                return value.boolValue
            }
            if let value = claims[key] as? String {
                switch value.lowercased() {
                case "true", "1":
                    return true
                case "false", "0":
                    return false
                default:
                    break
                }
            }
        }
        return defaultValue
    }

    private static func metadataString(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String {
            return string
        }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    /// Builds a minimal User from JWT access token claims when /me endpoint is unavailable.
    /// Tenants, roles, and permissions are synthesized from flat JWT fields.
    static func fromJWT(_ claims: [String: Any]) -> User? {
        guard let id = stringClaim(claims, keys: ["sub", "userId", "user_id"]) else { return nil }

        let email = stringClaim(claims, keys: ["email", "preferred_username", "upn"]) ?? id
        let name = stringClaim(claims, keys: ["name", "given_name", "preferred_username", "email"]) ?? email
        let tenantId = stringClaim(
            claims,
            keys: ["tenantId", "tenant_id", "activeTenantId", "active_tenant_id"]
        ) ?? stringArrayClaim(claims, keys: ["tenantIds", "tenant_ids"])?.first ?? "unknown"

        let tenantIds = stringArrayClaim(claims, keys: ["tenantIds", "tenant_ids"]) ?? [tenantId]
        let now = ISO8601DateFormatter().string(from: Date())

        let activeTenant = Tenant(
            id: tenantId, name: tenantId, tenantId: tenantId,
            createdAt: now, updatedAt: now, isReseller: false, metadata: "{}", vendorId: ""
        )

        let tenants = tenantIds.map { tid in
            Tenant(id: tid, name: tid, tenantId: tid,
                   createdAt: now, updatedAt: now, isReseller: false, metadata: "{}", vendorId: "")
        }

        let roleNames = claims["roles"] as? [String] ?? []
        let roles = roleNames.map { r in
            UserRole(id: r, key: r, isDefault: false, name: r, permissions: [],
                     vendorId: "", createdAt: now, updatedAt: now)
        }

        let permKeys = claims["permissions"] as? [String] ?? []
        let permissions = permKeys.map { p in
            UserRolePermission(id: p, key: p, name: p, categoryId: "",
                               fePermission: false, createdAt: now, updatedAt: now)
        }

        return User(
            id: id, email: email, mfaEnrolled: boolClaim(claims, keys: ["mfaEnrolled", "mfa_enrolled"]),
            name: name,
            profilePictureUrl: stringClaim(claims, keys: ["profilePictureUrl", "profileImage", "picture"]) ?? "",
            phoneNumber: stringClaim(claims, keys: ["phoneNumber", "phone_number"]),
            profileImage: stringClaim(claims, keys: ["profileImage", "profile_image"]),
            roles: roles, permissions: permissions,
            tenantId: tenantId, tenantIds: tenantIds,
            tenants: tenants, activeTenant: activeTenant,
            activatedForTenant: boolClaim(claims, keys: ["activatedForTenant", "activated_for_tenant"], default: true),
            metadata: metadataString(claims["metadata"]),
            verified: boolClaim(claims, keys: ["email_verified", "verified"]),
            superUser: boolClaim(claims, keys: ["superUser", "super_user"])
        )
    }

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
        self.tenants = try container.decode([Tenant].self, forKey: .tenants)
        self.activeTenant = try container.decode(Tenant.self, forKey: .activeTenant)
        self.activatedForTenant = (try? container.decodeIfPresent(Bool.self, forKey: .activatedForTenant)) ?? false
        self.metadata = try container.decodeIfPresent(String.self, forKey: .metadata)
        
        self.verified = (try? container.decodeIfPresent(Bool.self, forKey: .verified)) ?? false
        self.superUser = (try? container.decodeIfPresent(Bool.self, forKey: .superUser)) ?? false
    }
    
    init(dictionary: [String: Any]) throws {
        self = try JSONDecoder().decode(User.self, from: JSONSerialization.data(withJSONObject: dictionary))
    }
    
    public static func == (lhs: User, rhs: User) -> Bool {
        return lhs.id == rhs.id &&
        lhs.email == rhs.email &&
        lhs.mfaEnrolled == rhs.mfaEnrolled &&
        lhs.name == rhs.name &&
        lhs.profilePictureUrl == rhs.profilePictureUrl &&
        lhs.phoneNumber == rhs.phoneNumber &&
        lhs.profileImage == rhs.profileImage &&
        lhs.roles == rhs.roles &&
        lhs.permissions == rhs.permissions &&
        lhs.tenantId == rhs.tenantId &&
        lhs.tenantIds == rhs.tenantIds &&
        lhs.tenants == rhs.tenants &&
        lhs.activeTenant == rhs.activeTenant &&
        lhs.activatedForTenant == rhs.activatedForTenant &&
        lhs.metadata == rhs.metadata &&
        lhs.verified == rhs.verified &&
        lhs.superUser == rhs.superUser
    }
}
