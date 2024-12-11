//
//  AuthenticationError.swift
//
//
//  Created by Nick Hagi on 17/07/2024.
//

import Foundation

// MARK: - AuthenticationError
extension FronteggError {
    
    public enum Authentication: LocalizedError {
        case couldNotExchangeToken(_ message: String)
        case failedToAuthenticate
        case failedToRefreshToken
        case failedToLoadUserData(_ message: String)
        case failedToExtractCode
        case failedToSwitchTenant
        case codeVerifierNotFound
        case couldNotFindRootViewController
        case invalidPasskeysRequest
        case failedToAuthenticateWithPasskeys(_ message: String)
        case operationCanceled
        case mfaRequired(_ json: [String:Any], refreshToken: String? = nil)
        case notAuthenticated
        case unknown
        case other(Error)
    }
}

// MARK: - LocalizedError
extension FronteggError.Authentication {

    public var errorDescription: String? {
        switch self {
        case let .couldNotExchangeToken(message): message
        case .failedToAuthenticate: "Failed to authenticate with frontegg"
        case .failedToRefreshToken: "Failed to refresh token"
        case let .failedToLoadUserData(message): "Failed to load user data: \(message)"
        case .failedToExtractCode: "Failed to get extract code from hostedLoginCallback url"
        case .failedToSwitchTenant: "Failed to switch tenant"
        case .codeVerifierNotFound: "Code verifier not found"
        case .couldNotFindRootViewController: "Unable to find root viewController"
        case .invalidPasskeysRequest: "Invalid passkeys request"
        case let .failedToAuthenticateWithPasskeys(message): "Failed to authenticate with Passkeys, \(message)"
        case .operationCanceled: "Operation canceled by user"
        case .mfaRequired: "MFA is required for authentication"
        case .notAuthenticated: "Not authenticated exception"
        case .unknown: "Unknown error occurred"
        case let .other(error): error.localizedDescription
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .couldNotExchangeToken: "couldNotExchangeToken"
        case .failedToAuthenticate: "failedToAuthenticate"
        case .failedToRefreshToken: "failedToRefreshToken"
        case .failedToLoadUserData: "failedToLoadUserData"
        case .failedToExtractCode: "failedToExtractCode"
        case .failedToSwitchTenant: "failedToSwitchTenant"
        case .codeVerifierNotFound: "codeVerifierNotFound"
        case .couldNotFindRootViewController: "couldNotFindRootViewController"
        case .invalidPasskeysRequest: "invalidPasskeysRequest"
        case .failedToAuthenticateWithPasskeys: "failedToAuthenticateWithPasskeys"
        case .operationCanceled: "operationCanceled"
        case .mfaRequired: "mfaRequired"
        case .notAuthenticated: "notAuthenticated"
        case .unknown: "unknown"
        case .other: "other"
        }
    }
}
