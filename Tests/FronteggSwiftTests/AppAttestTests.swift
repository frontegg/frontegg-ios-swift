//
//  AppAttestTests.swift
//  FronteggSwiftTests
//

import XCTest
import CryptoKit
import DeviceCheck
@testable import FronteggSwift

final class FakeAppAttestService: AppAttestServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _isSupportedReads = 0
    private var _generateKeyCalls = 0
    private var _attestCalls: [(keyId: String, clientDataHash: Data)] = []
    private var _assertionCalls: [(keyId: String, clientDataHash: Data)] = []
    private var _attestedKeys: Set<String> = []

    var supported: Bool
    var generateKeyDelay: UInt64 = 0
    var attestDelay: UInt64 = 0
    var attestErrors: [Error] = []
    var assertionErrors: [Error] = []
    var generateKeyError: Error?

    init(supported: Bool = true) {
        self.supported = supported
    }

    var isSupported: Bool {
        lock.lock(); defer { lock.unlock() }
        _isSupportedReads += 1
        return supported
    }

    var isSupportedReads: Int { lock.lock(); defer { lock.unlock() }; return _isSupportedReads }
    var generateKeyCalls: Int { lock.lock(); defer { lock.unlock() }; return _generateKeyCalls }
    var attestCalls: [(keyId: String, clientDataHash: Data)] { lock.lock(); defer { lock.unlock() }; return _attestCalls }
    var assertionCalls: [(keyId: String, clientDataHash: Data)] { lock.lock(); defer { lock.unlock() }; return _assertionCalls }
    var attestedKeys: Set<String> { lock.lock(); defer { lock.unlock() }; return _attestedKeys }
    var totalCalls: Int { isSupportedReads + generateKeyCalls + attestCalls.count + assertionCalls.count }

    func generateKey() async throws -> String {
        let index: Int = {
            lock.lock(); defer { lock.unlock() }
            _generateKeyCalls += 1
            return _generateKeyCalls
        }()
        if generateKeyDelay > 0 {
            try await Task.sleep(nanoseconds: generateKeyDelay)
        }
        if let generateKeyError { throw generateKeyError }
        return "key-\(index)"
    }

    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        lock.lock()
        _attestCalls.append((keyId, clientDataHash))
        lock.unlock()
        if attestDelay > 0 {
            try await Task.sleep(nanoseconds: attestDelay)
        }
        let error: Error? = {
            lock.lock(); defer { lock.unlock() }
            if !attestErrors.isEmpty { return attestErrors.removeFirst() }
            if _attestedKeys.contains(keyId) { return DCError(.invalidKey) }
            _attestedKeys.insert(keyId)
            return nil
        }()
        if let error { throw error }
        return Data("attestation:\(keyId)".utf8)
    }

    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        let error: Error? = {
            lock.lock(); defer { lock.unlock() }
            _assertionCalls.append((keyId, clientDataHash))
            return assertionErrors.isEmpty ? nil : assertionErrors.removeFirst()
        }()
        if let error { throw error }
        return Data("assertion:\(keyId)".utf8)
    }
}

final class InMemoryAppAttestKeyStore: AppAttestKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var record: AppAttestKeyRecord?
    private(set) var saveCount = 0
    var loadError: Error?

    init(keyId: String? = nil, attested: Bool = false) {
        self.record = keyId.map { AppAttestKeyRecord(keyId: $0, attested: attested) }
    }

    func loadKey() throws -> AppAttestKeyRecord? {
        lock.lock(); defer { lock.unlock() }
        if let loadError { throw loadError }
        return record
    }

    func saveKey(_ record: AppAttestKeyRecord) throws {
        lock.lock(); defer { lock.unlock() }
        saveCount += 1
        self.record = record
    }

    func deleteKey() {
        lock.lock(); defer { lock.unlock() }
        record = nil
    }
}

final class AppAttestTests: XCTestCase {

    private func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    private func assertThrows<T>(
        _ expected: FronteggAppAttestError,
        _ body: () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await body()
            XCTFail("Expected \(expected) to be thrown", file: file, line: line)
        } catch let error as FronteggAppAttestError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error \(error)", file: file, line: line)
        }
    }

    // MARK: - Opt-in

    func test_disabled_neverTouchesService() async {
        let service = FakeAppAttestService()
        let store = InMemoryAppAttestKeyStore()
        let appAttest = FronteggAppAttest(isEnabled: false, service: service, keyStore: store)

        XCTAssertFalse(appAttest.isEnabled)
        XCTAssertFalse(appAttest.isSupported)
        await assertThrows(.disabled) { try await appAttest.generateKey() }
        await assertThrows(.disabled) { try await appAttest.attestKey(challenge: Data("c".utf8)) }
        await assertThrows(.disabled) { try await appAttest.generateAssertion(for: Data("r".utf8)) }
        await assertThrows(.disabled) { try await appAttest.assertionHeaders(for: Data("r".utf8)) }

        XCTAssertEqual(service.totalCalls, 0)
        XCTAssertEqual(store.saveCount, 0)
    }

    func test_unsupportedDevice_throwsTypedError() async {
        let service = FakeAppAttestService(supported: false)
        let appAttest = FronteggAppAttest(isEnabled: true, service: service, keyStore: InMemoryAppAttestKeyStore())

        XCTAssertFalse(appAttest.isSupported)
        await assertThrows(.unsupported) { try await appAttest.generateKey() }
        await assertThrows(.unsupported) { try await appAttest.attestKey(challenge: Data("c".utf8)) }
        await assertThrows(.unsupported) { try await appAttest.generateAssertion(for: Data("r".utf8)) }
        XCTAssertEqual(service.generateKeyCalls, 0)
    }

    func test_featureUnsupportedFromService_mapsToUnsupported() async {
        let service = FakeAppAttestService()
        service.generateKeyError = DCError(.featureUnsupported)
        let appAttest = FronteggAppAttest(isEnabled: true, service: service, keyStore: InMemoryAppAttestKeyStore())

        await assertThrows(.unsupported) { try await appAttest.generateKey() }
    }

    // MARK: - Key lifecycle

    func test_generateKey_persistsAndReusesAcrossInstances() async throws {
        let service = FakeAppAttestService()
        let store = InMemoryAppAttestKeyStore()

        let first = FronteggAppAttest(isEnabled: true, service: service, keyStore: store)
        let keyId = try await first.generateKey()
        let again = try await first.generateKey()

        let second = FronteggAppAttest(isEnabled: true, service: service, keyStore: store)
        let reloaded = try await second.generateKey()

        XCTAssertEqual(keyId, "key-1")
        XCTAssertEqual(again, keyId)
        XCTAssertEqual(reloaded, keyId)
        XCTAssertEqual(service.generateKeyCalls, 1)
        XCTAssertEqual(try store.loadKey(), AppAttestKeyRecord(keyId: keyId, attested: false))
    }

    func test_concurrentCalls_generateSingleKey() async throws {
        let service = FakeAppAttestService()
        service.generateKeyDelay = 50_000_000
        let appAttest = FronteggAppAttest(isEnabled: true, service: service, keyStore: InMemoryAppAttestKeyStore())

        let keyIds = try await withThrowingTaskGroup(of: String.self) { group -> [String] in
            for _ in 0..<10 {
                group.addTask { try await appAttest.generateKey() }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        XCTAssertEqual(service.generateKeyCalls, 1)
        XCTAssertEqual(Set(keyIds), ["key-1"])
    }

    func test_resetKey_forcesNewKeyOnNextUse() async throws {
        let service = FakeAppAttestService()
        let store = InMemoryAppAttestKeyStore()
        let appAttest = FronteggAppAttest(isEnabled: true, service: service, keyStore: store)

        _ = try await appAttest.generateKey()
        await appAttest.resetKey()
        XCTAssertNil(try store.loadKey())

        let next = try await appAttest.generateKey()
        XCTAssertEqual(next, "key-2")
    }

    // MARK: - Attestation

    func test_attestKey_usesSha256OfChallengeAsClientDataHash() async throws {
        let service = FakeAppAttestService()
        let appAttest = FronteggAppAttest(isEnabled: true, service: service, keyStore: InMemoryAppAttestKeyStore())
        let challenge = Data("server-challenge-123".utf8)

        let attestation = try await appAttest.attestKey(challenge: challenge)

        XCTAssertEqual(attestation.keyId, "key-1")
        XCTAssertEqual(attestation.attestationObject, Data("attestation:key-1".utf8))
        XCTAssertEqual(service.attestCalls.count, 1)
        XCTAssertEqual(service.attestCalls.first?.keyId, "key-1")
        XCTAssertEqual(service.attestCalls.first?.clientDataHash, sha256(challenge))
        XCTAssertEqual(service.attestCalls.first?.clientDataHash.count, 32)
    }

    func test_attestKey_invalidKey_regeneratesAndRetriesOnce() async throws {
        let service = FakeAppAttestService()
        service.attestErrors = [DCError(.invalidKey)]
        let store = InMemoryAppAttestKeyStore(keyId: "stale-key")
        let appAttest = FronteggAppAttest(isEnabled: true, service: service, keyStore: store)

        let attestation = try await appAttest.attestKey(challenge: Data("c".utf8))

        XCTAssertEqual(service.attestCalls.map(\.keyId), ["stale-key", "key-1"])
        XCTAssertEqual(service.generateKeyCalls, 1)
        XCTAssertEqual(attestation.keyId, "key-1")
        XCTAssertEqual(try store.loadKey(), AppAttestKeyRecord(keyId: "key-1", attested: true))
    }

    func test_attestKey_invalidInput_regeneratesAndRetriesOnce() async throws {
        let service = FakeAppAttestService()
        service.attestErrors = [DCError(.invalidInput)]
        let appAttest = FronteggAppAttest(isEnabled: true, service: service, keyStore: InMemoryAppAttestKeyStore(keyId: "stale-key"))

        let attestation = try await appAttest.attestKey(challenge: Data("c".utf8))

        XCTAssertEqual(attestation.keyId, "key-1")
        XCTAssertEqual(service.attestCalls.count, 2)
    }

    func test_attestKey_invalidKeyTwice_givesUpAfterSingleRetry() async {
        let service = FakeAppAttestService()
        service.attestErrors = [DCError(.invalidKey), DCError(.invalidKey)]
        let store = InMemoryAppAttestKeyStore(keyId: "stale-key")
        let appAttest = FronteggAppAttest(isEnabled: true, service: service, keyStore: store)

        await assertThrows(.invalidKey) { try await appAttest.attestKey(challenge: Data("c".utf8)) }
        XCTAssertEqual(service.attestCalls.count, 2)
        XCTAssertEqual(service.generateKeyCalls, 1)
        XCTAssertNil(try store.loadKey())
    }

    func test_attestKey_serverUnavailable_mapsToServiceError() async {
        let service = FakeAppAttestService()
        service.attestErrors = [DCError(.serverUnavailable)]
        let appAttest = FronteggAppAttest(isEnabled: true, service: service, keyStore: InMemoryAppAttestKeyStore())

        await assertThrows(.serverUnavailable) { try await appAttest.attestKey(challenge: Data("c".utf8)) }
        XCTAssertEqual(service.attestCalls.count, 1)
    }

    // MARK: - Assertion

    func test_generateAssertion_usesSha256OfRequestData() async throws {
        let service = FakeAppAttestService()
        let appAttest = FronteggAppAttest(isEnabled: true, service: service, keyStore: InMemoryAppAttestKeyStore(keyId: "attested-key", attested: true))
        let requestData = Data(#"{"challenge":"abc","body":"payload"}"#.utf8)

        let assertion = try await appAttest.generateAssertion(for: requestData)

        XCTAssertEqual(assertion.keyId, "attested-key")
        XCTAssertEqual(assertion.assertion, Data("assertion:attested-key".utf8))
        XCTAssertEqual(service.assertionCalls.first?.clientDataHash, sha256(requestData))
        XCTAssertEqual(service.generateKeyCalls, 0)
    }

    func test_generateAssertion_invalidKey_dropsKeyAndRequiresReattestation() async throws {
        let service = FakeAppAttestService()
        service.assertionErrors = [DCError(.invalidKey)]
        let store = InMemoryAppAttestKeyStore(keyId: "revoked-key", attested: true)
        let appAttest = FronteggAppAttest(isEnabled: true, service: service, keyStore: store)

        await assertThrows(.keyInvalidated) { try await appAttest.generateAssertion(for: Data("r".utf8)) }
        XCTAssertNil(try store.loadKey())
        XCTAssertEqual(service.assertionCalls.count, 1)

        let attestation = try await appAttest.attestKey(challenge: Data("c".utf8))
        XCTAssertEqual(attestation.keyId, "key-1")
    }

    func test_generateAssertion_withoutKey_requiresAttestationFirst() async {
        let service = FakeAppAttestService()
        let appAttest = FronteggAppAttest(isEnabled: true, service: service, keyStore: InMemoryAppAttestKeyStore())

        await assertThrows(.keyNotAttested) { try await appAttest.generateAssertion(for: Data("r".utf8)) }
        XCTAssertEqual(service.generateKeyCalls, 0)
        XCTAssertTrue(service.assertionCalls.isEmpty)
    }

    func test_assertionHeaders_carryKeyIdAndBase64Assertion() async throws {
        let service = FakeAppAttestService()
        let appAttest = FronteggAppAttest(isEnabled: true, service: service, keyStore: InMemoryAppAttestKeyStore(keyId: "attested-key", attested: true))

        let headers = try await appAttest.assertionHeaders(for: Data("r".utf8))

        XCTAssertEqual(headers, [
            FronteggAppAttest.keyIdHeader: "attested-key",
            FronteggAppAttest.assertionHeader: Data("assertion:attested-key".utf8).base64EncodedString()
        ])
        XCTAssertEqual(FronteggAppAttest.keyIdHeader, "X-Frontegg-App-Attest-Key-Id")
        XCTAssertEqual(FronteggAppAttest.assertionHeader, "X-Frontegg-App-Attest-Assertion")
    }

    // MARK: - Attested key protection

    func test_attestKey_secondCall_throwsAlreadyAttestedWithoutRotatingKey() async throws {
        let service = FakeAppAttestService()
        let store = InMemoryAppAttestKeyStore()
        let appAttest = FronteggAppAttest(isEnabled: true, service: service, keyStore: store)

        let attestation = try await appAttest.attestKey(challenge: Data("c1".utf8))
        await assertThrows(.keyAlreadyAttested) { try await appAttest.attestKey(challenge: Data("c2".utf8)) }

        XCTAssertEqual(attestation.keyId, "key-1")
        XCTAssertEqual(service.attestCalls.map(\.keyId), ["key-1"])
        XCTAssertEqual(service.generateKeyCalls, 1)
        XCTAssertEqual(try store.loadKey(), AppAttestKeyRecord(keyId: "key-1", attested: true))
        let assertion = try await appAttest.generateAssertion(for: Data("r".utf8))
        XCTAssertEqual(assertion.keyId, "key-1")
    }

    func test_attestKey_attestedKeyFromPreviousLaunch_isNotReattested() async throws {
        let service = FakeAppAttestService()
        let store = InMemoryAppAttestKeyStore()
        _ = try await FronteggAppAttest(isEnabled: true, service: service, keyStore: store)
            .attestKey(challenge: Data("c1".utf8))

        let relaunched = FronteggAppAttest(isEnabled: true, service: service, keyStore: store)
        let isAttested = try await relaunched.isKeyAttested()
        XCTAssertTrue(isAttested)
        await assertThrows(.keyAlreadyAttested) { try await relaunched.attestKey(challenge: Data("c2".utf8)) }

        XCTAssertEqual(service.attestCalls.count, 1)
        XCTAssertEqual(service.generateKeyCalls, 1)
        XCTAssertEqual(try store.loadKey()?.keyId, "key-1")
    }

    func test_concurrentAttestAndAssert_doNotRotateKey() async throws {
        let service = FakeAppAttestService()
        service.attestDelay = 50_000_000
        let store = InMemoryAppAttestKeyStore()
        let appAttest = FronteggAppAttest(isEnabled: true, service: service, keyStore: store)

        enum Outcome: Equatable { case attested(String), asserted(String), error(FronteggAppAttestError) }

        let outcomes = await withTaskGroup(of: Outcome.self) { group -> [Outcome] in
            for index in 0..<6 {
                group.addTask {
                    do {
                        if index < 3 {
                            return .attested(try await appAttest.attestKey(challenge: Data("c\(index)".utf8)).keyId)
                        }
                        try await Task.sleep(nanoseconds: 20_000_000)
                        return .asserted(try await appAttest.generateAssertion(for: Data("r\(index)".utf8)).keyId)
                    } catch let error as FronteggAppAttestError {
                        return .error(error)
                    } catch {
                        return .error(.failed("\(error)"))
                    }
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }

        XCTAssertEqual(outcomes.filter { $0 == .attested("key-1") }.count, 1)
        XCTAssertEqual(outcomes.filter { $0 == .error(.keyAlreadyAttested) }.count, 2)
        XCTAssertEqual(outcomes.filter { $0 == .asserted("key-1") }.count, 3)
        XCTAssertEqual(service.generateKeyCalls, 1)
        XCTAssertEqual(service.attestCalls.map(\.keyId), ["key-1"])
        XCTAssertEqual(try store.loadKey(), AppAttestKeyRecord(keyId: "key-1", attested: true))
    }

    func test_resetKey_allowsExplicitReattestationWithNewKey() async throws {
        let service = FakeAppAttestService()
        let store = InMemoryAppAttestKeyStore()
        let appAttest = FronteggAppAttest(isEnabled: true, service: service, keyStore: store)

        _ = try await appAttest.attestKey(challenge: Data("c1".utf8))
        await appAttest.resetKey()
        let isAttested = try await appAttest.isKeyAttested()
        XCTAssertFalse(isAttested)
        let second = try await appAttest.attestKey(challenge: Data("c2".utf8))

        XCTAssertEqual(second.keyId, "key-2")
        XCTAssertEqual(service.attestCalls.map(\.keyId), ["key-1", "key-2"])
        XCTAssertEqual(try store.loadKey(), AppAttestKeyRecord(keyId: "key-2", attested: true))
    }

    func test_generateAssertion_unattestedStoredKey_requiresAttestation() async throws {
        let service = FakeAppAttestService()
        let store = InMemoryAppAttestKeyStore(keyId: "generated-only")
        let appAttest = FronteggAppAttest(isEnabled: true, service: service, keyStore: store)

        await assertThrows(.keyNotAttested) { try await appAttest.generateAssertion(for: Data("r".utf8)) }
        XCTAssertTrue(service.assertionCalls.isEmpty)

        let attestation = try await appAttest.attestKey(challenge: Data("c".utf8))
        XCTAssertEqual(attestation.keyId, "generated-only")
        XCTAssertEqual(service.generateKeyCalls, 0)
    }

    // MARK: - Locked keychain

    func test_lockedKeychainRead_throwsWithoutGeneratingKey() async {
        let service = FakeAppAttestService()
        let store = InMemoryAppAttestKeyStore(keyId: "attested-key", attested: true)
        store.loadError = CredentialManager.KeychainError.keychainUnavailable(errSecInteractionNotAllowed)
        let appAttest = FronteggAppAttest(isEnabled: true, service: service, keyStore: store)

        for call in [
            { _ = try await appAttest.generateKey() },
            { _ = try await appAttest.attestKey(challenge: Data("c".utf8)) },
            { _ = try await appAttest.generateAssertion(for: Data("r".utf8)) }
        ] as [() async throws -> Void] {
            do {
                try await call()
                XCTFail("Expected locked keychain read to throw")
            } catch FronteggAppAttestError.failed {
            } catch {
                XCTFail("Unexpected error \(error)")
            }
        }

        XCTAssertEqual(service.generateKeyCalls, 0)
        XCTAssertTrue(service.attestCalls.isEmpty)
        XCTAssertTrue(service.assertionCalls.isEmpty)
        XCTAssertEqual(store.saveCount, 0)
    }

    func test_keychainKeyStore_lockedKeychain_throwsInsteadOfReportingNoKey() {
        let credentials = CredentialManager(serviceKey: "frontegg-test-locked.appattest")
        credentials.copyMatching = { _, _ in errSecInteractionNotAllowed }
        let store = KeychainAppAttestKeyStore(credentialManager: credentials)

        XCTAssertThrowsError(try store.loadKey())

        credentials.copyMatching = { _, _ in errSecItemNotFound }
        XCTAssertNil(try store.loadKey())
    }

    // MARK: - Keychain store

    func test_keychainKeyStore_roundTripsAndIsIsolatedFromSessionClear() throws {
        let service = "frontegg-test-\(UUID().uuidString)"
        let sessionCredentials = CredentialManager(serviceKey: service)
        do {
            try sessionCredentials.save(key: "__probe__", value: "1")
            sessionCredentials.delete(key: "__probe__")
        } catch {
            throw XCTSkip("Keychain unavailable in this environment: \(error)")
        }

        let store = KeychainAppAttestKeyStore(keychainService: service)
        defer { store.deleteKey() }
        let record = AppAttestKeyRecord(keyId: "persisted-key", attested: true)

        XCTAssertNil(try store.loadKey())
        try store.saveKey(record)
        XCTAssertEqual(try KeychainAppAttestKeyStore(keychainService: service).loadKey(), record)

        sessionCredentials.clear()
        XCTAssertEqual(try store.loadKey(), record)

        store.deleteKey()
        XCTAssertNil(try store.loadKey())
    }

    // MARK: - Plist flag

    private func decodePlist(_ extra: [String: Any]) throws -> FronteggPlist {
        var dict: [String: Any] = [
            "baseUrl": "https://test.com",
            "clientId": "d37ad699-e466-451a-a9d1-d590869dba1a"
        ]
        dict.merge(extra) { $1 }
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        return try PlistHelper.decode(FronteggPlist.self, from: data, at: "testPath")
    }

    func test_plist_enableAppAttest_defaultsToFalse() throws {
        XCTAssertFalse(try decodePlist([:]).enableAppAttest)
    }

    func test_plist_enableAppAttest_decodesTrue() throws {
        XCTAssertTrue(try decodePlist(["enableAppAttest": true]).enableAppAttest)
    }
}
