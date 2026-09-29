//
//  FronteggSecurityCenterService.swift
//  FronteggSwift
//

import Foundation
import Combine

extension FronteggAuth {
    var mainThreadUserPublisher: AnyPublisher<User?, Never> {
        $user
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .prepend(user)
            .eraseToAnyPublisher()
    }
}

protocol FronteggSecurityCenterService: AnyObject {
    func listSessions() async throws -> [FronteggSession]
    func revokeSession(id: String) async throws
    func revokeOtherSessions() async throws
    func listPasskeys() async throws -> [FronteggPasskey]
    func deletePasskey(id: String) async throws
    func registerPasskey() async throws
    func stepUp(maxAge: TimeInterval?) async throws
    func isSteppedUp(maxAge: TimeInterval?) -> Bool
}

protocol FronteggTenantSwitching: AnyObject {
    func switchTenant(tenantId: String) async throws -> User
}

final class FronteggAuthSecurityCenterService: FronteggSecurityCenterService {
    private let auth: FronteggAuth

    init(auth: FronteggAuth) {
        self.auth = auth
    }

    private var api: FronteggSecurityAPI {
        FronteggSecurityAPI(
            baseUrl: auth.baseUrl,
            applicationId: auth.applicationId,
            accessTokenProvider: { [auth] in try await auth.getOrRefreshAccessTokenAsync() },
            transport: FronteggSecurityAPI.urlSessionTransport
        )
    }

    func listSessions() async throws -> [FronteggSession] {
        try await api.listSessions()
    }

    func revokeSession(id: String) async throws {
        try await api.revokeSession(id: id)
    }

    func revokeOtherSessions() async throws {
        try await api.revokeOtherSessions()
    }

    func listPasskeys() async throws -> [FronteggPasskey] {
        try await api.listPasskeys()
    }

    func deletePasskey(id: String) async throws {
        try await api.deletePasskey(id: id)
    }

    func registerPasskey() async throws {
        guard #available(iOS 15.0, *) else {
            throw FronteggError.authError(.invalidPasskeysRequest)
        }
        let auth = self.auth
        let error: FronteggError? = await withCheckedContinuation { continuation in
            let resumed = OnceFlag()
            DispatchQueue.main.async {
                auth.registerPasskeys { error in
                    if resumed.set() { continuation.resume(returning: error) }
                }
            }
        }
        if let error { throw error }
    }

    func stepUp(maxAge: TimeInterval?) async throws {
        let auth = self.auth
        let result: Result<User, FronteggError> = await withCheckedContinuation { continuation in
            let resumed = OnceFlag()
            Task { @MainActor in
                await auth.stepUp(maxAge: maxAge) { result in
                    if resumed.set() { continuation.resume(returning: result) }
                }
            }
        }
        _ = try result.get()
    }

    func isSteppedUp(maxAge: TimeInterval?) -> Bool {
        auth.isSteppedUp(maxAge: maxAge)
    }
}

final class FronteggAuthTenantSwitcher: FronteggTenantSwitching {
    private let auth: FronteggAuth

    init(auth: FronteggAuth) {
        self.auth = auth
    }

    func switchTenant(tenantId: String) async throws -> User {
        let auth = self.auth
        let result: Result<User, FronteggError> = await withCheckedContinuation { continuation in
            let resumed = OnceFlag()
            auth.switchTenant(tenantId: tenantId) { result in
                if resumed.set() { continuation.resume(returning: result) }
            }
        }
        return try result.get()
    }
}

final class OnceFlag {
    private let lock = NSLock()
    private var isSet = false

    func set() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if isSet { return false }
        isSet = true
        return true
    }
}
