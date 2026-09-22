//
//  FronteggSecurityCenterViewModel.swift
//  FronteggSwift
//

import Foundation
import Combine

@MainActor
final class FronteggSecurityCenterViewModel: ObservableObject {

    @Published private(set) var sessions: [FronteggSession] = []
    @Published private(set) var passkeys: [FronteggPasskey] = []
    @Published private(set) var isLoadingSessions = false
    @Published private(set) var isLoadingPasskeys = false
    @Published private(set) var sessionsError: String?
    @Published private(set) var passkeysError: String?
    @Published private(set) var pendingIds: Set<String> = []
    @Published private(set) var isRevokingOtherSessions = false
    @Published private(set) var isAddingPasskey = false
    @Published private(set) var isSteppingUp = false
    @Published private(set) var user: User?
    @Published var errorMessage: String?

    private let service: FronteggSecurityCenterService
    private let stepUpMaxAge: TimeInterval?

    init(
        service: FronteggSecurityCenterService,
        userPublisher: AnyPublisher<User?, Never>,
        stepUpMaxAge: TimeInterval? = nil
    ) {
        self.service = service
        self.stepUpMaxAge = stepUpMaxAge
        userPublisher.assign(to: &$user)
    }

    var mfaEnrolled: Bool {
        user?.mfaEnrolled ?? false
    }

    var activeTenantName: String? {
        user?.activeTenant.name
    }

    var isSteppedUp: Bool {
        service.isSteppedUp(maxAge: stepUpMaxAge)
    }

    var otherSessions: [FronteggSession] {
        sessions.filter { !$0.isCurrent }
    }

    func load() async {
        async let sessionsLoad: Void = loadSessions()
        async let passkeysLoad: Void = loadPasskeys()
        _ = await (sessionsLoad, passkeysLoad)
    }

    func loadSessions() async {
        isLoadingSessions = true
        defer { isLoadingSessions = false }
        do {
            let loaded = try await service.listSessions()
            sessions = loaded.filter(\.isCurrent) + loaded.filter { !$0.isCurrent }
            sessionsError = nil
        } catch {
            sessionsError = Self.message(for: error)
        }
    }

    func loadPasskeys() async {
        isLoadingPasskeys = true
        defer { isLoadingPasskeys = false }
        do {
            passkeys = try await service.listPasskeys()
            passkeysError = nil
        } catch {
            passkeysError = Self.message(for: error)
        }
    }

    func revoke(_ session: FronteggSession) async {
        guard !session.isCurrent, !pendingIds.contains(session.id) else { return }
        pendingIds.insert(session.id)
        defer { pendingIds.remove(session.id) }
        do {
            try await service.revokeSession(id: session.id)
            await loadSessions()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func revokeOtherSessions() async {
        guard !isRevokingOtherSessions else { return }
        isRevokingOtherSessions = true
        defer { isRevokingOtherSessions = false }
        do {
            try await service.revokeOtherSessions()
            await loadSessions()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func delete(_ passkey: FronteggPasskey) async {
        guard !pendingIds.contains(passkey.id) else { return }
        pendingIds.insert(passkey.id)
        defer { pendingIds.remove(passkey.id) }
        do {
            try await service.deletePasskey(id: passkey.id)
            await loadPasskeys()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func addPasskey() async {
        guard !isAddingPasskey else { return }
        isAddingPasskey = true
        defer { isAddingPasskey = false }
        do {
            try await service.registerPasskey()
            await loadPasskeys()
        } catch {
            if !Self.isCancellation(error) {
                errorMessage = Self.message(for: error)
            }
        }
    }

    func stepUp() async {
        guard !isSteppingUp else { return }
        isSteppingUp = true
        defer { isSteppingUp = false }
        do {
            try await service.stepUp(maxAge: stepUpMaxAge)
        } catch {
            if !Self.isCancellation(error) {
                errorMessage = Self.message(for: error)
            }
        }
        objectWillChange.send()
    }

    static func message(for error: Error) -> String {
        error.localizedDescription
    }

    static func isCancellation(_ error: Error) -> Bool {
        if case .authError(let authError)? = error as? FronteggError {
            switch authError {
            case .operationCanceled:
                return true
            case .other(let underlying):
                return FronteggAuth.isUserCancelledOAuthFlow(underlying)
            default:
                return false
            }
        }
        return FronteggAuth.isUserCancelledOAuthFlow(error)
    }
}
