//
//  GoogleIdTokenProvider.swift
//  FronteggSwift
//

import Foundation
import UIKit

/// Supplies Google ID tokens for native Google sign-in, for example `FronteggGoogleSignIn`.
public protocol FronteggGoogleIdTokenProvider: AnyObject {
    /// Returns an ID token whose audience is `serverClientId`, and throws `.authError(.operationCanceled)` on cancel.
    @MainActor
    func idToken(serverClientId: String, presenting viewController: UIViewController) async throws -> String
}

final class FronteggGoogleIdTokenProviderBox {
    private let lock = NSLock()
    private var provider: FronteggGoogleIdTokenProvider?

    var value: FronteggGoogleIdTokenProvider? {
        get { lock.withLock { provider } }
        set { lock.withLock { provider = newValue } }
    }
}

enum FronteggGoogleSignInRuntimeSettings {
    static let providerBox = FronteggGoogleIdTokenProviderBox()
}
