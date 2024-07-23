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
        case failedToLoadUserData(_ message: String)
        case failedToExtractCode
        case failedToSwitchTenant
        case codeVerifierNotFound
        case couldNotFindRootViewController
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
        case let .failedToLoadUserData(message): "Failed to load user data: \(message)"
        case .failedToExtractCode: "Failed to get extract code from hostedLoginCallback url"
        case .failedToSwitchTenant: "Failed to switch tenant"
        case .codeVerifierNotFound: "Code verifier not found"
        case .couldNotFindRootViewController: "Unable to find root viewController"
        case .unknown: "Unknown error occurred"
        case let .other(error): error.localizedDescription
        }
    }
}
