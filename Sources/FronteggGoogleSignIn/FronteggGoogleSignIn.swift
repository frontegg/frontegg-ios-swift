//
//  FronteggGoogleSignIn.swift
//  FronteggGoogleSignIn
//

import Foundation
import UIKit
import FronteggSwift
import GoogleSignIn

/// Google ID tokens from the Google Sign-In SDK; set it as `FronteggApp.shared.googleSignIn`.
public final class FronteggGoogleSignIn: FronteggGoogleIdTokenProvider {

    private let clientId: String?

    /// `clientId` is the app's iOS OAuth client ID and defaults to `GIDClientID` in Info.plist.
    public init(clientId: String? = nil) {
        self.clientId = clientId ?? Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
    }

    @MainActor
    public func idToken(serverClientId: String, presenting viewController: UIViewController) async throws -> String {
        guard let clientId, !clientId.isEmpty else {
            throw FronteggError.configError(.socialLoginMissing("Google: set GIDClientID in Info.plist or pass clientId"))
        }
        // GIDSignIn raises an uncatchable exception when this scheme is missing, so it is checked first.
        guard Self.isRedirectSchemeRegistered(for: clientId) else {
            throw FronteggError.configError(.socialLoginMissing("Google: add the reversed client ID as a URL scheme"))
        }
        let signIn = GIDSignIn.sharedInstance
        let appConfiguration = signIn.configuration
        let fronteggConfiguration = GIDConfiguration(clientID: clientId, serverClientID: serverClientId)
        signIn.configuration = fronteggConfiguration
        defer {
            if signIn.configuration === fronteggConfiguration {
                signIn.configuration = appConfiguration
            }
        }

        let result: GIDSignInResult
        do {
            result = try await signIn.signIn(withPresenting: viewController)
        } catch let error as GIDSignInError where error.code == .canceled {
            throw FronteggError.authError(.operationCanceled)
        }

        let idToken = result.user.idToken?.tokenString
        // Frontegg keeps no Google session, so the signed-in Google user is cleared; an app using Google itself signs in again.
        signIn.signOut()
        guard let idToken else {
            throw FronteggGoogleSignInError.missingIdToken
        }
        return idToken
    }

    private static func isRedirectSchemeRegistered(for clientId: String) -> Bool {
        let reversedClientId = clientId.split(separator: ".").reversed().joined(separator: ".")
        let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        return urlTypes.contains { urlType in
            let schemes = urlType["CFBundleURLSchemes"] as? [String] ?? []
            return schemes.contains { $0.caseInsensitiveCompare(reversedClientId) == .orderedSame }
        }
    }

    /// Passes a URL from `onOpenURL` or `application(_:open:options:)` to Google Sign-In.
    public static func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }
}

public enum FronteggGoogleSignInError: LocalizedError {
    case missingIdToken

    public var errorDescription: String? {
        switch self {
        case .missingIdToken: "Google Sign-In returned no ID token"
        }
    }
}
