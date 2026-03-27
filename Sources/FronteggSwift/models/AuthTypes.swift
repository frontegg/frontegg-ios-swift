//
//  AuthTypes.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import Foundation

public enum AttemptReasonType {
    case unknown
    case noNetwork
}

enum CredentialHydrationMode {
    case authoritative              // login, tenant-switch, passkey, apple auth — fetch /me
    case refreshPreserveCachedUser  // token refresh — prefer cached user
    case preserveCachedOrDerivedUser // callback recovery — keep cached/JWT user, skip a second /me
}

enum CredentialHydrationFailure: Error {
    case authoritativeUserLoadFailed(Error)
}

struct StoredSessionArtifacts {
    let accessToken: String?
    let refreshToken: String?
    let offlineUser: User?
    let tenantId: String?
}

struct OAuthFailureDetails {
    let error: FronteggError
    let errorCode: String?
    let errorDescription: String?
}
