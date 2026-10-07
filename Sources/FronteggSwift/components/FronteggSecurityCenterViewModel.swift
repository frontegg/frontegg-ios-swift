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

    private(set) var tenantChangeReload: Task<Void, Never>?

    private let service: FronteggSecurityCenterService
    private let stepUpMaxAge: TimeInterval?
    private let loadsSessions: Bool
    private let loadsPasskeys: Bool
    private let logger = getLogger("FronteggSecurityCenterViewModel")
    private var sessionsGeneration = 0
    private var passkeysGeneration = 0
    private var cancellables = Set<AnyCancellable>()

    init(
        service: FronteggSecurityCenterService,
        userPublisher: AnyPublisher<User?, Never>,
        stepUpMaxAge: TimeInterval? = nil,
        loadsSessions: Bool = true,
        loadsPasskeys: Bool = true
    ) {
        self.service = service
        self.stepUpMaxAge = stepUpMaxAge
        self.loadsSessions = loadsSessions
        self.loadsPasskeys = loadsPasskeys
        userPublisher.assign(to: &$user)
        $user
            .map { $0?.activeTenant.tenantId }
            .removeDuplicates()
            .scan((String?.none, String?.none)) { ($0.1, $1) }
            .filter { $0.0 != nil && $0.1 != nil }
            .sink { [weak self] _ in self?.reloadAfterTenantChange() }
            .store(in: &cancellables)
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
        async let sessionsLoad: Void = loadsSessions ? loadSessions() : ()
        async let passkeysLoad: Void = loadsPasskeys ? loadPasskeys() : ()
        _ = await (sessionsLoad, passkeysLoad)
    }

    func loadSessions() async {
        sessionsGeneration += 1
        let generation = sessionsGeneration
        isLoadingSessions = true
        defer { if generation == sessionsGeneration { isLoadingSessions = false } }
        do {
            let loaded = try await service.listSessions()
            guard generation == sessionsGeneration else { return }
            sessions = loaded.filter(\.isCurrent) + loaded.filter { !$0.isCurrent }
            sessionsError = nil
        } catch {
            guard generation == sessionsGeneration, !Self.isTaskCancellation(error) else { return }
            logger.error("Failed to load sessions: \(error.localizedDescription)")
            sessionsError = Self.message(for: error)
        }
    }

    func loadPasskeys() async {
        passkeysGeneration += 1
        let generation = passkeysGeneration
        isLoadingPasskeys = true
        defer { if generation == passkeysGeneration { isLoadingPasskeys = false } }
        do {
            let loaded = try await service.listPasskeys()
            guard generation == passkeysGeneration else { return }
            passkeys = loaded
            passkeysError = nil
        } catch {
            guard generation == passkeysGeneration, !Self.isTaskCancellation(error) else { return }
            logger.error("Failed to load passkeys: \(error.localizedDescription)")
            passkeysError = Self.message(for: error)
        }
    }

    private func reloadAfterTenantChange() {
        tenantChangeReload = Task { [weak self] in
            await self?.load()
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
            logger.error("Failed to revoke session: \(error.localizedDescription)")
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
            logger.error("Failed to revoke other sessions: \(error.localizedDescription)")
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
            logger.error("Failed to delete passkey: \(error.localizedDescription)")
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
                logger.error("Failed to register passkey: \(error.localizedDescription)")
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
                logger.error("Step-up failed: \(error.localizedDescription)")
                errorMessage = Self.message(for: error)
            }
        }
        objectWillChange.send()
    }

    static func message(for error: Error) -> String {
        error.localizedDescription
    }

    static func isTaskCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
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
