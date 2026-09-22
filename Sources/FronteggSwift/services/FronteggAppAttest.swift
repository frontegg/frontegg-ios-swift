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
    /// No attested App Attest key exists yet; call ``FronteggAppAttest/attestKey(challenge:)`` first.
    case keyNotAttested
    /// The stored key is already attested and can sign assertions. Apple allows a key to be
    /// attested only once; call ``FronteggAppAttest/resetKey()`` first to attest a new key.
    case keyAlreadyAttested
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

struct AppAttestKeyRecord: Codable, Equatable {
    let keyId: String
    var attested: Bool
}

protocol AppAttestKeyStore: Sendable {
    func loadKey() throws -> AppAttestKeyRecord?
    func saveKey(_ record: AppAttestKeyRecord) throws
    func deleteKey()
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
    static let keyAccount = "fe_appAttestKey"

    private let credentialManager: CredentialManager

    init(credentialManager: CredentialManager) {
        self.credentialManager = credentialManager
    }

    convenience init(keychainService: String) {
        self.init(credentialManager: CredentialManager(serviceKey: "\(keychainService).appattest"))
    }

    func loadKey() throws -> AppAttestKeyRecord? {
        do {
            guard let value = try credentialManager.get(key: Self.keyAccount) else { return nil }
            return try JSONDecoder().decode(AppAttestKeyRecord.self, from: Data(value.utf8))
        } catch CredentialManager.KeychainError.unknown(let status) where status == errSecItemNotFound {
            return nil
        }
    }

    func saveKey(_ record: AppAttestKeyRecord) throws {
        let data = try JSONEncoder().encode(record)
        try credentialManager.save(key: Self.keyAccount, value: String(decoding: data, as: UTF8.self))
    }

    func deleteKey() {
        credentialManager.delete(key: Self.keyAccount)
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
    private var cachedRecord: AppAttestKeyRecord?
    private var lastOperation: Task<Void, Never>?

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
        return try await serialized { try await self.currentOrNewRecord().keyId }
    }

    /// Whether the stored key has been attested and can sign assertions.
    public func isKeyAttested() async throws -> Bool {
        try ensureAvailable()
        return try await serialized { try self.storedRecord()?.attested ?? false }
    }

    /// Attests the current key using `SHA256(challenge)` as the client data hash.
    ///
    /// `challenge` must be a one-time value issued by your server. A key can be attested only
    /// once: if the stored key is already attested this throws
    /// ``FronteggAppAttestError/keyAlreadyAttested`` without contacting Apple; call
    /// ``resetKey()`` first to attest a new key. If the system rejects a key that has not been
    /// attested yet, a new key is generated and attestation is retried once.
    public func attestKey(challenge: Data) async throws -> FronteggAppAttestation {
        try ensureAvailable()
        let clientDataHash = Self.sha256(challenge)
        return try await serialized { try await self.performAttestation(clientDataHash: clientDataHash) }
    }

    /// Signs `SHA256(requestData)` with the attested key.
    ///
    /// Throws ``FronteggAppAttestError/keyNotAttested`` when no attested key exists and
    /// ``FronteggAppAttestError/keyInvalidated`` when the key is no longer valid; in both
    /// cases call ``attestKey(challenge:)`` before retrying.
    public func generateAssertion(for requestData: Data) async throws -> FronteggAppAttestAssertion {
        try ensureAvailable()
        let clientDataHash = Self.sha256(requestData)
        return try await serialized { try await self.performAssertion(clientDataHash: clientDataHash) }
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

    /// Removes the stored key so the next ``attestKey(challenge:)`` generates and attests a new key.
    public func resetKey() async {
        _ = try? await serialized { self.clearKey() }
    }

    private func serialized<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        let previous = lastOperation
        let task = Task { () async throws -> T in
            await previous?.value
            return try await operation()
        }
        lastOperation = Task { _ = try? await task.value }
        return try await task.value
    }

    private func performAttestation(clientDataHash: Data) async throws -> FronteggAppAttestation {
        let record = try await currentOrNewRecord()
        guard !record.attested else {
            throw FronteggAppAttestError.keyAlreadyAttested
        }

        do {
            return try await attest(record.keyId, clientDataHash: clientDataHash)
        } catch let error where Self.isRejectedKey(error) {
            logger.warning("Unattested App Attest key rejected during attestation, generating a new key")
            clearKey()
        } catch {
            throw Self.map(error)
        }

        let fresh = try await currentOrNewRecord()
        do {
            return try await attest(fresh.keyId, clientDataHash: clientDataHash)
        } catch let error where Self.isRejectedKey(error) {
            clearKey()
            throw FronteggAppAttestError.invalidKey
        } catch {
            throw Self.map(error)
        }
    }

    private func attest(_ keyId: String, clientDataHash: Data) async throws -> FronteggAppAttestation {
        let object = try await service.attestKey(keyId, clientDataHash: clientDataHash)
        store(AppAttestKeyRecord(keyId: keyId, attested: true))
        return FronteggAppAttestation(keyId: keyId, attestationObject: object)
    }

    private func performAssertion(clientDataHash: Data) async throws -> FronteggAppAttestAssertion {
        guard let record = try storedRecord(), record.attested else {
            throw FronteggAppAttestError.keyNotAttested
        }

        do {
            let assertion = try await service.generateAssertion(record.keyId, clientDataHash: clientDataHash)
            return FronteggAppAttestAssertion(keyId: record.keyId, assertion: assertion)
        } catch let error where Self.isRejectedKey(error) {
            logger.warning("Attested App Attest key rejected during assertion, re-attestation required")
            clearKey()
            throw FronteggAppAttestError.keyInvalidated
        } catch {
            throw Self.map(error)
        }
    }

    private func ensureAvailable() throws {
        guard isEnabled else { throw FronteggAppAttestError.disabled }
        guard service.isSupported else { throw FronteggAppAttestError.unsupported }
    }

    private func storedRecord() throws -> AppAttestKeyRecord? {
        if let cachedRecord {
            return cachedRecord
        }
        do {
            cachedRecord = try keyStore.loadKey()
        } catch {
            logger.warning("Failed to read App Attest key from keychain: \(error)")
            throw FronteggAppAttestError.failed("\(error)")
        }
        return cachedRecord
    }

    private func currentOrNewRecord() async throws -> AppAttestKeyRecord {
        if let record = try storedRecord() {
            return record
        }
        let keyId: String
        do {
            keyId = try await service.generateKey()
        } catch {
            throw Self.map(error)
        }
        let record = AppAttestKeyRecord(keyId: keyId, attested: false)
        store(record)
        return record
    }

    private func store(_ record: AppAttestKeyRecord) {
        cachedRecord = record
        do {
            try keyStore.saveKey(record)
        } catch {
            logger.warning("Failed to persist App Attest key state: \(error)")
        }
    }

    private func clearKey() {
        cachedRecord = nil
        keyStore.deleteKey()
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
