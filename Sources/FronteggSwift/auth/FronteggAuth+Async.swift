//
//  FronteggAuth+Async.swift
//

import Foundation

extension FronteggAuth {

    /// Async variant of `login(_:loginHint:)`.
    /// - Throws: `FronteggError`; inspect `category` to branch on the cause.
    public func loginAsync(loginHint: String? = nil) async throws -> User {
        try await awaitCompletion { completion in
            self.login(completion, loginHint: loginHint)
        }
    }

    /// Async variant of `switchTenant(tenantId:_:)`.
    /// - Throws: `FronteggError`; inspect `category` to branch on the cause.
    public func switchTenantAsync(tenantId: String) async throws -> User {
        try await awaitCompletion { completion in
            self.switchTenant(tenantId: tenantId, completion)
        }
    }

    /// Async variant of `logout(clearCookie:_:)`.
    /// - Throws: `FronteggError`; inspect `category` to branch on the cause.
    public func logoutAsync(clearCookie: Bool = true) async throws {
        _ = try await awaitCompletion { completion in
            self.logout(clearCookie: clearCookie, completion)
        }
    }

    private func awaitCompletion<T>(
        _ start: (@escaping (Result<T, FronteggError>) -> Void) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var resumed = false
            start { result in
                let isFirst = lock.withLock { () -> Bool in
                    defer { resumed = true }
                    return !resumed
                }
                if isFirst {
                    continuation.resume(with: result)
                }
            }
        }
    }
}
