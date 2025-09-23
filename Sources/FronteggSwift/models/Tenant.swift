//
//  Tenant.swift
//  
//
//  Created by David Frontegg on 14/08/2023.
//

import Foundation


public struct Tenant: Codable, Equatable {
    
    enum DecodeError: Error {
        case invalidJsonData
    }
    
    public var id: String
    public var name: String
    public var creatorEmail:String?
    public var creatorName:String?
    public var tenantId: String
    public var createdAt: String
    public var updatedAt: String
    public var isReseller: Bool
    public var metadata: String
    public var vendorId: String
    public var website: String?

}
