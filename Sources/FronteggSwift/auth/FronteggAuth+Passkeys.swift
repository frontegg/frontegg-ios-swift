//
//  FronteggAuth+Passkeys.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import Foundation

extension FronteggAuth {

    public func loginWithPasskeys(_ _completion: FronteggAuth.CompletionHandler? = nil) {
        if #available(iOS 15.0, *) {
            Task {
                let completion = handleMfaRequired(FronteggAuth.onMainThread(_completion))
                await PasskeysAuthenticator.shared.loginWithPasskeys(completion)
            }
        } else {
            // Fallback on earlier versions
        }
    }

    public func registerPasskeys(_ completion: FronteggAuth.ConditionCompletionHandler? = nil) {
        if #available(iOS 15.0, *) {
            PasskeysAuthenticator.shared.startWebAuthn(FronteggAuth.onMainThread(completion))
        } else {
            // Fallback on earlier versions
        }
    }
}
