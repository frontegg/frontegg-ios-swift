//
//  FronteggAppAttest.swift
//

import Foundation
import CryptoKit
import DeviceCheck

/// Errors thrown by ``FronteggAppAttest``.
public enum FronteggAppAttestError: Error, Equatable {
    /// `enableAppAttest` is not set in `Frontegg.plist`.
    case disabled
    /// App Attest is not available (simulator, unsupported device, or missing entitlement).
    case unsupported
    /// No App Attest key exists yet; call ``FronteggAppAttest/attestKey(challenge:)`` first.
    case keyNotAttested
    /// The stored key was rejected by the system; attest a new key with ``FronteggAppAttest/attestKey(challenge:)``.
    case keyInvalidated
    /// The system rejected the key again after a fresh key was generated.
    case invalidKey
    /// Apple's App Attest service could not be reached; retry later.
    case serverUnavailable
    /// Any other DeviceCheck or system failure.
    case failed(String)
}

/// The result of attesting an App Attest key. Send both values to your server for verification.
public struct FronteggAppAttestation: Equatable {
    public let keyId: String
    /// CBOR-encoded attestation object returned by `DCAppAttestService`.
    public let attestationObject: Data
}

/// An assertion signed by the attested key over `SHA256(requestData)`.
public struct FronteggAppAttestAssertion: Equatable {
    public let keyId: String
    /// CBOR-encoded assertion returned by `DCAppAttestService`.
    public let assertion: Data
}

protocol AppAttestServiceProtocol: Sendable {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data
}

protocol AppAttestKeyStore: Sendable {
    func loadKeyId() throws -> String?
    func saveKeyId(_ keyId: String) throws
    func deleteKeyId()
}

struct DeviceCheckAppAttestService: AppAttestServiceProtocol {
    var isSupported: Bool {
        DCAppAttestService.shared.isSupported
    }

    func generateKey() async throws -> String {
        try await DCAppAttestService.shared.generateKey()
    }

    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.attestKey(keyId, clientDataHash: clientDataHash)
    }

    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: clientDataHash)
    }
}

final class KeychainAppAttestKeyStore: AppAttestKeyStore, @unchecked Sendable {
    static let keyIdAccount = "fe_appAttestKeyId"

    private let credentialManager: CredentialManager

    init(keychainService: String) {
        self.credentialManager = CredentialManager(serviceKey: "\(keychainService).appattest")
    }

    func loadKeyId() throws -> String? {
        do {
            return try credentialManager.get(key: Self.keyIdAccount)
        } catch CredentialManager.KeychainError.unknown(let status) where status == errSecItemNotFound {
            return nil
        }
    }

    func saveKeyId(_ keyId: String) throws {
        try credentialManager.save(key: Self.keyIdAccount, value: keyId)
    }

    func deleteKeyId() {
        credentialManager.delete(key: Self.keyIdAccount)
    }
}

/// Opt-in App Attest (DeviceCheck) support.
///
/// Enable with `enableAppAttest` in `Frontegg.plist` and add the
/// `com.apple.developer.devicecheck.appattest-environment` entitlement to the app.
/// The SDK does not send attestations or assertions to Frontegg; use this API to
/// attest the app to your own backend.
public actor FronteggAppAttest {

    /// Header carrying the attested key identifier.
    public static let keyIdHeader = "X-Frontegg-App-Attest-Key-Id"
    /// Header carrying the base64-encoded assertion.
    public static let assertionHeader = "X-Frontegg-App-Attest-Assertion"

    /// Whether App Attest was enabled in `Frontegg.plist`.
    public nonisolated let isEnabled: Bool

    private let service: AppAttestServiceProtocol
    private let keyStore: AppAttestKeyStore
    private let logger = getLogger("FronteggAppAttest")
    private var cachedKeyId: String?
    private var pendingKeyGeneration: Task<String, Error>?

    init(isEnabled: Bool, service: AppAttestServiceProtocol, keyStore: AppAttestKeyStore) {
        self.isEnabled = isEnabled
        self.service = service
        self.keyStore = keyStore
    }

    init(isEnabled: Bool, keychainService: String) {
        self.init(
            isEnabled: isEnabled,
            service: DeviceCheckAppAttestService(),
            keyStore: KeychainAppAttestKeyStore(keychainService: keychainService)
        )
    }

    /// `true` when App Attest is enabled and available on this device. Always `false` on the simulator.
    public nonisolated var isSupported: Bool {
        isEnabled && service.isSupported
    }

    /// Returns the persisted App Attest key identifier, generating and storing a new key if none exists.
    public func generateKey() async throws -> String {
        try ensureAvailable()
        return try await currentOrNewKeyId()
    }

    /// Attests the current key using `SHA256(challenge)` as the client data hash.
    ///
    /// `challenge` must be a one-time value issued by your server. If the system rejects the
    /// stored key, a new key is generated and attestation is retried once.
    public func attestKey(challenge: Data) async throws -> FronteggAppAttestation {
        try ensureAvailable()
        let clientDataHash = Self.sha256(challenge)
        let keyId = try await currentOrNewKeyId()

        do {
            let object = try await service.attestKey(keyId, clientDataHash: clientDataHash)
            return FronteggAppAttestation(keyId: keyId, attestationObject: object)
        } catch let error where Self.isRejectedKey(error) {
            logger.warning("App Attest key rejected during attestation, generating a new key")
            discardKey(keyId)
        } catch {
            throw Self.map(error)
        }

        let freshKeyId = try await currentOrNewKeyId()
        do {
            let object = try await service.attestKey(freshKeyId, clientDataHash: clientDataHash)
            return FronteggAppAttestation(keyId: freshKeyId, attestationObject: object)
        } catch let error where Self.isRejectedKey(error) {
            discardKey(freshKeyId)
            throw FronteggAppAttestError.invalidKey
        } catch {
            throw Self.map(error)
        }
    }

    /// Signs `SHA256(requestData)` with the attested key.
    ///
    /// Throws ``FronteggAppAttestError/keyNotAttested`` when no key exists and
    /// ``FronteggAppAttestError/keyInvalidated`` when the key is no longer valid; in both
    /// cases call ``attestKey(challenge:)`` before retrying.
    public func generateAssertion(for requestData: Data) async throws -> FronteggAppAttestAssertion {
        try ensureAvailable()
        guard let keyId = try await existingKeyId() else {
            throw FronteggAppAttestError.keyNotAttested
        }

        do {
            let assertion = try await service.generateAssertion(keyId, clientDataHash: Self.sha256(requestData))
            return FronteggAppAttestAssertion(keyId: keyId, assertion: assertion)
        } catch let error where Self.isRejectedKey(error) {
            logger.warning("App Attest key rejected during assertion, re-attestation required")
            discardKey(keyId)
            throw FronteggAppAttestError.keyInvalidated
        } catch {
            throw Self.map(error)
        }
    }

    /// Returns ``keyIdHeader`` and ``assertionHeader`` values for a request whose
    /// client data is `requestData`. The SDK does not attach these to Frontegg requests.
    public func assertionHeaders(for requestData: Data) async throws -> [String: String] {
        let result = try await generateAssertion(for: requestData)
        return [
            Self.keyIdHeader: result.keyId,
            Self.assertionHeader: result.assertion.base64EncodedString()
        ]
    }

    /// Removes the stored key identifier so the next call generates a new key.
    public func resetKey() {
        cachedKeyId = nil
        keyStore.deleteKeyId()
    }

    private func ensureAvailable() throws {
        guard isEnabled else { throw FronteggAppAttestError.disabled }
        guard service.isSupported else { throw FronteggAppAttestError.unsupported }
    }

    private func existingKeyId() async throws -> String? {
        if let pendingKeyGeneration {
            return try await pendingKeyGeneration.value
        }
        if let cachedKeyId {
            return cachedKeyId
        }
        do {
            cachedKeyId = try keyStore.loadKeyId()
        } catch {
            logger.warning("Failed to read App Attest key id from keychain: \(error)")
            throw FronteggAppAttestError.failed("\(error)")
        }
        return cachedKeyId
    }

    private func currentOrNewKeyId() async throws -> String {
        if let keyId = try await existingKeyId() {
            return keyId
        }

        let task = Task { try await self.createKey() }
        pendingKeyGeneration = task
        return try await task.value
    }

    private func createKey() async throws -> String {
        defer { pendingKeyGeneration = nil }
        let keyId: String
        do {
            keyId = try await service.generateKey()
        } catch {
            throw Self.map(error)
        }
        do {
            try keyStore.saveKeyId(keyId)
        } catch {
            logger.warning("Failed to persist App Attest key id, it will be regenerated on next launch: \(error)")
        }
        cachedKeyId = keyId
        return keyId
    }

    private func discardKey(_ keyId: String) {
        guard cachedKeyId == nil || cachedKeyId == keyId else { return }
        cachedKeyId = nil
        keyStore.deleteKeyId()
    }

    static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    private static func isRejectedKey(_ error: Error) -> Bool {
        guard let error = error as? DCError else { return false }
        return error.code == .invalidKey || error.code == .invalidInput
    }

    private static func map(_ error: Error) -> FronteggAppAttestError {
        if let error = error as? FronteggAppAttestError {
            return error
        }
        guard let error = error as? DCError else {
            return .failed("\(error)")
        }
        switch error.code {
        case .featureUnsupported:
            return .unsupported
        case .serverUnavailable:
            return .serverUnavailable
        case .invalidKey, .invalidInput:
            return .invalidKey
        default:
            return .failed(error.localizedDescription)
        }
    }
}
