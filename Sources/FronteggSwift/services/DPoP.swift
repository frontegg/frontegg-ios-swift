//
//  DPoP.swift
//

import CryptoKit
import Foundation

public enum FronteggDPoPError: Error {
    case disabled
    case missingAccessToken
}

struct DPoPKeyStorage {
    let load: () -> String?
    let save: (String) -> Void
    let delete: () -> Void

    static let keychainAccount = "fe_dpop_signing_key"

    static func keychain(_ credentialManager: CredentialManager) -> DPoPKeyStorage {
        DPoPKeyStorage(
            load: { try? credentialManager.get(key: keychainAccount) },
            save: { try? credentialManager.save(key: keychainAccount, value: $0) },
            delete: { credentialManager.delete(key: keychainAccount) }
        )
    }
}

/// Generates RFC 9449 DPoP proofs with a per-install P-256 key (Secure Enclave when available).
public final class FronteggDPoP {

    private enum SigningKey {
        case secureEnclave(SecureEnclave.P256.Signing.PrivateKey)
        case software(P256.Signing.PrivateKey)

        private static let secureEnclavePrefix = "se:"
        private static let softwarePrefix = "sw:"

        var publicKey: P256.Signing.PublicKey {
            switch self {
            case .secureEnclave(let key): return key.publicKey
            case .software(let key): return key.publicKey
            }
        }

        func signature(for data: Data) throws -> Data {
            switch self {
            case .secureEnclave(let key): return try key.signature(for: data).rawRepresentation
            case .software(let key): return try key.signature(for: data).rawRepresentation
            }
        }

        var serialized: String {
            switch self {
            case .secureEnclave(let key): return Self.secureEnclavePrefix + key.dataRepresentation.base64EncodedString()
            case .software(let key): return Self.softwarePrefix + key.rawRepresentation.base64EncodedString()
            }
        }

        init?(serialized: String) {
            if serialized.hasPrefix(Self.secureEnclavePrefix),
               let data = Data(base64Encoded: String(serialized.dropFirst(Self.secureEnclavePrefix.count))),
               let key = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data) {
                self = .secureEnclave(key)
            } else if serialized.hasPrefix(Self.softwarePrefix),
                      let data = Data(base64Encoded: String(serialized.dropFirst(Self.softwarePrefix.count))),
                      let key = try? P256.Signing.PrivateKey(rawRepresentation: data) {
                self = .software(key)
            } else {
                return nil
            }
        }

        static func generate(preferSecureEnclave: Bool) -> SigningKey {
            if preferSecureEnclave, let key = try? SecureEnclave.P256.Signing.PrivateKey() {
                return .secureEnclave(key)
            }
            return .software(P256.Signing.PrivateKey())
        }
    }

    private static let keyLock = NSLock()

    private let logger = getLogger("FronteggDPoP")
    private let storage: DPoPKeyStorage
    private let preferSecureEnclave: Bool
    private let clock: () -> Date
    private let jtiGenerator: () -> String
    private let nonceLock = NSLock()
    private var nonces: [String: String] = [:]

    init(
        storage: DPoPKeyStorage,
        preferSecureEnclave: Bool = SecureEnclave.isAvailable,
        clock: @escaping () -> Date = Date.init,
        jtiGenerator: @escaping () -> String = { UUID().uuidString }
    ) {
        self.storage = storage
        self.preferSecureEnclave = preferSecureEnclave
        self.clock = clock
        self.jtiGenerator = jtiGenerator
    }

    convenience init(credentialManager: CredentialManager) {
        self.init(storage: .keychain(credentialManager))
    }

    /// Returns a signed DPoP proof JWT for the given request.
    /// - Parameters:
    ///   - accessToken: when set, the proof carries `ath` (required when calling a resource server with a DPoP-bound token).
    ///   - nonce: a server-provided `DPoP-Nonce` value.
    public func proof(method: String, url: URL, accessToken: String? = nil, nonce: String? = nil) throws -> String {
        let key = loadOrCreateKey()

        let header: [String: Any] = [
            "typ": "dpop+jwt",
            "alg": "ES256",
            "jwk": Self.jwk(for: key.publicKey),
        ]

        var claims: [String: Any] = [
            "jti": jtiGenerator(),
            "htm": method.uppercased(),
            "htu": Self.htu(for: url),
            "iat": Int(clock().timeIntervalSince1970),
        ]
        if let nonce {
            claims["nonce"] = nonce
        }
        if let accessToken {
            claims["ath"] = Self.accessTokenHash(accessToken)
        }

        let signingInput = try "\(Self.encode(header)).\(Self.encode(claims))"
        let signature = try key.signature(for: Data(signingInput.utf8))
        return "\(signingInput).\(signature.toEncodedBase64())"
    }

    /// Returns `Authorization: DPoP <token>` and `DPoP: <proof>` headers for a resource-server request.
    public func authorizationHeaders(method: String, url: URL, accessToken: String) throws -> [String: String] {
        let proof = try proof(method: method, url: url, accessToken: accessToken, nonce: nonce(for: url))
        return [
            "Authorization": "DPoP \(accessToken)",
            "DPoP": proof,
        ]
    }

    /// The public key used for proofs, as a JWK.
    public func publicJWK() -> [String: String] {
        Self.jwk(for: loadOrCreateKey().publicKey)
    }

    /// RFC 7638 JWK thumbprint (`jkt`) of the proof key.
    public func thumbprint() -> String {
        let jwk = publicJWK()
        let canonical = "{\"crv\":\"\(jwk["crv"]!)\",\"kty\":\"\(jwk["kty"]!)\",\"x\":\"\(jwk["x"]!)\",\"y\":\"\(jwk["y"]!)\"}"
        return Data(SHA256.hash(data: Data(canonical.utf8))).toEncodedBase64()
    }

    /// Stores the latest `DPoP-Nonce` for the URL's origin.
    public func recordNonce(_ nonce: String, for url: URL) {
        guard let origin = Self.origin(of: url) else { return }
        nonceLock.withLock { nonces[origin] = nonce }
    }

    /// Stores the `DPoP-Nonce` header of a response, if present.
    public func recordNonce(from response: HTTPURLResponse) {
        guard let nonce = response.value(forHTTPHeaderField: "DPoP-Nonce"), let url = response.url else { return }
        recordNonce(nonce, for: url)
    }

    /// The latest `DPoP-Nonce` received from the URL's origin.
    public func nonce(for url: URL) -> String? {
        guard let origin = Self.origin(of: url) else { return nil }
        return nonceLock.withLock { nonces[origin] }
    }

    func rotateKey() {
        Self.keyLock.withLock { storage.delete() }
        nonceLock.withLock { nonces.removeAll() }
    }

    /// True when the response asks the client to retry with a server-provided nonce.
    public static func isNonceChallenge(_ response: HTTPURLResponse, data: Data) -> Bool {
        guard [400, 401].contains(response.statusCode),
              response.value(forHTTPHeaderField: "DPoP-Nonce") != nil else {
            return false
        }
        if let wwwAuthenticate = response.value(forHTTPHeaderField: "WWW-Authenticate"),
           wwwAuthenticate.contains("use_dpop_nonce") {
            return true
        }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["error"] as? String == "use_dpop_nonce"
    }

    static func htu(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return url.absoluteString
        }
        let scheme = components.scheme?.lowercased()
        components.scheme = scheme
        components.host = components.host?.lowercased()
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        if (scheme == "https" && components.port == 443) || (scheme == "http" && components.port == 80) {
            components.port = nil
        }
        if components.path.isEmpty {
            components.path = "/"
        }
        return components.string ?? url.absoluteString
    }

    static func accessTokenHash(_ accessToken: String) -> String {
        Data(SHA256.hash(data: Data(accessToken.utf8))).toEncodedBase64()
    }

    private static func origin(of url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return nil }
        if let port = url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    private static func jwk(for publicKey: P256.Signing.PublicKey) -> [String: String] {
        let raw = publicKey.rawRepresentation
        return [
            "kty": "EC",
            "crv": "P-256",
            "x": raw.prefix(32).toEncodedBase64(),
            "y": raw.suffix(32).toEncodedBase64(),
        ]
    }

    private static func encode(_ object: [String: Any]) throws -> String {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]).toEncodedBase64()
    }

    private func loadOrCreateKey() -> SigningKey {
        Self.keyLock.withLock {
            if let stored = storage.load() {
                if let key = SigningKey(serialized: stored) {
                    return key
                }
                logger.warning("Stored DPoP key is unreadable, generating a new one")
            }
            let key = SigningKey.generate(preferSecureEnclave: preferSecureEnclave)
            storage.save(key.serialized)
            return key
        }
    }
}
