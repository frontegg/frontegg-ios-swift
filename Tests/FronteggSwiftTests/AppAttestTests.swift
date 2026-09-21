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

    var supported: Bool
    var generateKeyDelay: UInt64 = 0
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
        let error: Error? = {
            lock.lock(); defer { lock.unlock() }
            _attestCalls.append((keyId, clientDataHash))
            return attestErrors.isEmpty ? nil : attestErrors.removeFirst()
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
    private var keyId: String?
    private(set) var saveCount = 0

    init(keyId: String? = nil) {
        self.keyId = keyId
    }

    func loadKeyId() throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return keyId
    }

    func saveKeyId(_ keyId: String) throws {
        lock.lock(); defer { lock.unlock() }
        saveCount += 1
        self.keyId = keyId
    }

    func deleteKeyId() {
        lock.lock(); defer { lock.unlock() }
        keyId = nil
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
        XCTAssertEqual(try store.loadKeyId(), keyId)
    }

    func test_concurrentCalls_generateSingleKey() async throws {
        let service = FakeAppAttestService()
        service.generateKeyDelay = 50_000_000
        let appAttest = FronteggAppAttest(isEnabled: true, service: service, keyStore: InMemoryAppAttestKeyStore())

        let keyIds = try await withThrowingTaskGroup(of: String.self) { group -> [String] in
            for index in 0..<10 {
                group.addTask {
                    if index.isMultiple(of: 2) {
                        return try await appAttest.generateKey()
                    }
                    return try await appAttest.attestKey(challenge: Data("c\(index)".utf8)).keyId
                }
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
        XCTAssertNil(try store.loadKeyId())

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
        XCTAssertEqual(try store.loadKeyId(), "key-1")
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
        XCTAssertNil(try store.loadKeyId())
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
        let appAttest = FronteggAppAttest(isEnabled: true, service: service, keyStore: InMemoryAppAttestKeyStore(keyId: "attested-key"))
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
        let store = InMemoryAppAttestKeyStore(keyId: "revoked-key")
        let appAttest = FronteggAppAttest(isEnabled: true, service: service, keyStore: store)

        await assertThrows(.keyInvalidated) { try await appAttest.generateAssertion(for: Data("r".utf8)) }
        XCTAssertNil(try store.loadKeyId())
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
        let appAttest = FronteggAppAttest(isEnabled: true, service: service, keyStore: InMemoryAppAttestKeyStore(keyId: "attested-key"))

        let headers = try await appAttest.assertionHeaders(for: Data("r".utf8))

        XCTAssertEqual(headers, [
            FronteggAppAttest.keyIdHeader: "attested-key",
            FronteggAppAttest.assertionHeader: Data("assertion:attested-key".utf8).base64EncodedString()
        ])
        XCTAssertEqual(FronteggAppAttest.keyIdHeader, "X-Frontegg-App-Attest-Key-Id")
        XCTAssertEqual(FronteggAppAttest.assertionHeader, "X-Frontegg-App-Attest-Assertion")
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
        defer { store.deleteKeyId() }

        XCTAssertNil(try store.loadKeyId())
        try store.saveKeyId("persisted-key")
        XCTAssertEqual(try KeychainAppAttestKeyStore(keychainService: service).loadKeyId(), "persisted-key")

        sessionCredentials.clear()
        XCTAssertEqual(try store.loadKeyId(), "persisted-key")

        store.deleteKeyId()
        XCTAssertNil(try store.loadKeyId())
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
