//
//  FronteggSecurityModels.swift
//  FronteggSwift
//

import Foundation

/// An active login session of the current user.
public struct FronteggSession: Identifiable, Equatable, Sendable {

    /// Platform inferred from the session's user agent.
    public enum Platform: String, Equatable, Sendable {
        case iPhone
        case iPad
        case mac
        case android
        case windows
        case linux
        case unknown
    }

    public let id: String
    public let ipAddress: String?
    public let userAgent: String?
    public let createdAt: Date?
    public let expires: Date?
    public let isCurrent: Bool
    public let isImpersonated: Bool

    public init(
        id: String,
        ipAddress: String? = nil,
        userAgent: String? = nil,
        createdAt: Date? = nil,
        expires: Date? = nil,
        isCurrent: Bool = false,
        isImpersonated: Bool = false
    ) {
        self.id = id
        self.ipAddress = ipAddress
        self.userAgent = userAgent
        self.createdAt = createdAt
        self.expires = expires
        self.isCurrent = isCurrent
        self.isImpersonated = isImpersonated
    }

    public var platform: Platform {
        guard let userAgent else { return .unknown }
        if userAgent.contains("iPhone") { return .iPhone }
        if userAgent.contains("iPad") { return .iPad }
        if userAgent.contains("Android") { return .android }
        if userAgent.contains("Macintosh") || userAgent.contains("Mac OS X") { return .mac }
        if userAgent.contains("Windows") { return .windows }
        if userAgent.contains("Linux") || userAgent.contains("X11") { return .linux }
        return .unknown
    }

    func markingCurrent(_ isCurrent: Bool) -> FronteggSession {
        FronteggSession(
            id: id,
            ipAddress: ipAddress,
            userAgent: userAgent,
            createdAt: createdAt,
            expires: expires,
            isCurrent: isCurrent,
            isImpersonated: isImpersonated
        )
    }
}

/// A passkey (WebAuthn device) registered for the current user.
public struct FronteggPasskey: Identifiable, Equatable, Sendable {

    public enum DeviceType: Equatable, Sendable {
        case platform
        case crossPlatform
        case other(String)

        init(rawValue: String) {
            switch rawValue {
            case "Platform": self = .platform
            case "CrossPlatform": self = .crossPlatform
            default: self = .other(rawValue)
            }
        }
    }

    public let id: String
    public let deviceType: DeviceType
    public let createdAt: Date?

    public init(id: String, deviceType: DeviceType, createdAt: Date? = nil) {
        self.id = id
        self.deviceType = deviceType
        self.createdAt = createdAt
    }
}

/// Errors raised by the security center networking layer.
public enum FronteggSecurityCenterError: LocalizedError, Equatable {
    case notAuthenticated
    case invalidResponse
    case requestFailed(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You are not signed in."
        case .invalidResponse:
            return "The server returned an unexpected response."
        case let .requestFailed(statusCode):
            return "The request failed (HTTP \(statusCode))."
        }
    }
}

struct SessionDTO: Decodable {
    let id: String
    let ipAddress: String?
    let userAgent: String?
    let createdAt: String?
    let expires: String?
    let current: Bool?
    let impersonated: Bool?

    var model: FronteggSession {
        FronteggSession(
            id: id,
            ipAddress: ipAddress,
            userAgent: userAgent,
            createdAt: FronteggDateParser.parse(createdAt),
            expires: FronteggDateParser.parse(expires),
            isCurrent: current ?? false,
            isImpersonated: impersonated ?? false
        )
    }
}

struct WebAuthnDevicesDTO: Decodable {
    struct Device: Decodable {
        let id: String
        let deviceType: String?
        let createdAt: String?
    }

    let devices: [Device]

    var models: [FronteggPasskey] {
        devices.map {
            FronteggPasskey(
                id: $0.id,
                deviceType: .init(rawValue: $0.deviceType ?? ""),
                createdAt: FronteggDateParser.parse($0.createdAt)
            )
        }
    }
}

enum FronteggDateParser {
    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }
}
