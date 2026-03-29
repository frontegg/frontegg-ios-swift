//
//  FronteggAuth+StepUp.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import Foundation

extension FronteggAuth {

    /// Checks if the user has been stepped up (re-authenticated with stronger authentication).
    public func isSteppedUp(maxAge: TimeInterval? = nil) -> Bool {
        return self.stepUpAuthenticator.isSteppedUp(maxAge: maxAge)
    }

    /// Initiates a step-up authentication process.
    public func stepUp(
        maxAge: TimeInterval? = nil,
        _ _completion: FronteggAuth.CompletionHandler? = nil
    ) async {
        return self.stepUpAuthenticator.stepUp(maxAge: maxAge, completion: _completion)
    }
}
