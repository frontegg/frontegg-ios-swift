//
//  FronteggErrorCategory.swift
//

import Foundation
import AuthenticationServices

/// A stable, coarse classification of any error surfaced by the SDK.
///
/// Use it to branch on the cause of a failure without matching every
/// `FronteggError` case. New categories may be added in future releases,
/// so include a `default` branch when switching over it.
public enum FronteggErrorCategory: Equatable {
    /// The device could not reach the server (offline, timeout, DNS, TLS, connection lost).
    case network
    /// The user or the system cancelled the operation.
    case cancelled
    /// The server requires multi-factor authentication to continue.
    case mfaRequired
    /// Switching the active tenant failed.
    case tenantSwitchFailed
    /// There is no valid session; the user has to sign in again.
    case notAuthenticated
    /// The server rejected the credentials or the authentication flow failed.
    case authenticationFailed
    /// The SDK or host app is misconfigured (Frontegg.plist, regions, presentation context).
    case configuration
    /// The server response could not be parsed or was missing required data.
    case invalidResponse
    /// The server answered with an unexpected HTTP status.
    case server(statusCode: Int)
    /// The cause could not be determined.
    case unknown

    /// A stable string identifier, suitable for bridging to other platforms.
    public var code: String {
        switch self {
        case .network: "network"
        case .cancelled: "cancelled"
        case .mfaRequired: "mfaRequired"
        case .tenantSwitchFailed: "tenantSwitchFailed"
        case .notAuthenticated: "notAuthenticated"
        case .authenticationFailed: "authenticationFailed"
        case .configuration: "configuration"
        case .invalidResponse: "invalidResponse"
        case .server: "server"
        case .unknown: "unknown"
        }
    }

    /// Classifies any error, looking through `FronteggError` wrappers to the underlying cause.
    public init(_ error: Error) {
        switch error {
        case let error as FronteggError:
            self = error.category
        case let error as FronteggError.Authentication:
            self = error.category
        case is FronteggError.Configuration:
            self = .configuration
        case let error as ApiError:
            switch error {
            case .invalidUrl:
                self = .configuration
            case let .refreshEndpointTransient(statusCode, _):
                self = .server(statusCode: statusCode)
            case let .meEndpointFailed(statusCode, _):
                self = statusCode == 401 ? .notAuthenticated : .server(statusCode: statusCode)
            }
        case is CancellationError:
            self = .cancelled
        case is DecodingError:
            self = .invalidResponse
        default:
            self = Self.classify(error as NSError)
        }
    }

    private static func classify(_ error: NSError) -> FronteggErrorCategory {
        switch error.domain {
        case ASWebAuthenticationSessionError.errorDomain:
            return error.code == ASWebAuthenticationSessionError.canceledLogin.rawValue ? .cancelled : .configuration
        case ASAuthorizationError.errorDomain:
            return error.code == ASAuthorizationError.canceled.rawValue ? .cancelled : .authenticationFailed
        case NSURLErrorDomain:
            switch URLError.Code(rawValue: error.code) {
            case .cancelled:
                return .cancelled
            case .badServerResponse, .cannotParseResponse, .cannotDecodeRawData, .cannotDecodeContentData, .zeroByteResource:
                return .invalidResponse
            default:
                return .network
            }
        default:
            return isConnectivityError(error) ? .network : .unknown
        }
    }
}

extension FronteggError {

    /// The coarse cause of this error. See `FronteggErrorCategory`.
    public var category: FronteggErrorCategory {
        switch self {
        case .configError: .configuration
        case .networkError: .network
        case let .authError(error): error.category
        }
    }

    /// The error wrapped by `.other`, if any.
    public var underlyingError: Error? {
        switch self {
        case .authError(.other(let error)), .networkError(.other(let error)): error
        default: nil
        }
    }

    /// Returns `error` as a `FronteggError`, wrapping foreign errors in `.authError(.other(_))`
    /// so the original cause stays available through `underlyingError` and `category`.
    public static func from(_ error: Error) -> FronteggError {
        switch error {
        case let error as FronteggError: error
        case let error as FronteggError.Authentication: .authError(error)
        case let error as FronteggError.Configuration: .configError(error)
        default: .authError(.other(error))
        }
    }
}

extension FronteggError.Authentication {

    /// The coarse cause of this error. See `FronteggErrorCategory`.
    public var category: FronteggErrorCategory {
        switch self {
        case .operationCanceled: .cancelled
        case .mfaRequired: .mfaRequired
        case .failedToSwitchTenant: .tenantSwitchFailed
        case .notAuthenticated, .failedToRefreshToken: .notAuthenticated
        case .invalidResponse, .failedToExtractCode: .invalidResponse
        case .couldNotFindRootViewController: .configuration
        case .failedToAuthenticate, .couldNotExchangeToken, .failedToLoadUserData, .failedToMFA,
             .codeVerifierNotFound, .invalidOAuthState, .invalidPasskeysRequest,
             .failedToAuthenticateWithPasskeys, .oauthError:
            .authenticationFailed
        case .unknown: .unknown
        case let .other(error): FronteggErrorCategory(error)
        }
    }
}
