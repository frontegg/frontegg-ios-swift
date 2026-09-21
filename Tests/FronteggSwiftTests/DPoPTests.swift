//
//  DPoPTests.swift
//  FronteggSwiftTests
//

import CryptoKit
import XCTest
@testable import FronteggSwift

private final class InMemoryDPoPKeyStorage {
    var value: String?

    var storage: DPoPKeyStorage {
        DPoPKeyStorage(
            load: { [unowned self] in self.value },
            save: { [unowned self] in self.value = $0 },
            delete: { [unowned self] in self.value = nil }
        )
    }
}

private struct DecodedProof {
    let header: [String: Any]
    let claims: [String: Any]
    let signingInput: Data
    let signature: Data

    init(_ jwt: String) throws {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(parts.count, 3)
        header = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(parts[0].toDecodedData())) as? [String: Any])
        claims = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(parts[1].toDecodedData())) as? [String: Any])
        signingInput = Data("\(parts[0]).\(parts[1])".utf8)
        signature = try XCTUnwrap(parts[2].toDecodedData())
    }

    var jwk: [String: String] { header["jwk"] as? [String: String] ?? [:] }

    func publicKey() throws -> P256.Signing.PublicKey {
        let x = try XCTUnwrap(jwk["x"]?.toDecodedData())
        let y = try XCTUnwrap(jwk["y"]?.toDecodedData())
        return try P256.Signing.PublicKey(x963Representation: Data([0x04]) + x + y)
    }
}

final class DPoPTests: XCTestCase {

    private var keyStorage: InMemoryDPoPKeyStorage!
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        super.setUp()
        keyStorage = InMemoryDPoPKeyStorage()
    }

    private func makeDPoP(jti: (() -> String)? = nil) -> FronteggDPoP {
        let fixedDate = self.fixedDate
        if let jti {
            return FronteggDPoP(storage: keyStorage.storage, preferSecureEnclave: false, clock: { fixedDate }, jtiGenerator: jti)
        }
        return FronteggDPoP(storage: keyStorage.storage, preferSecureEnclave: false, clock: { fixedDate })
    }

    func test_proof_hasDPoPJwtHeaderWithPublicJwkOnly() throws {
        let proof = try DecodedProof(makeDPoP().proof(method: "POST", url: URL(string: "https://auth.example.com/oauth/token")!))

        XCTAssertEqual(proof.header["typ"] as? String, "dpop+jwt")
        XCTAssertEqual(proof.header["alg"] as? String, "ES256")
        XCTAssertEqual(proof.jwk["kty"], "EC")
        XCTAssertEqual(proof.jwk["crv"], "P-256")
        XCTAssertEqual(proof.jwk["x"]?.toDecodedData()?.count, 32)
        XCTAssertEqual(proof.jwk["y"]?.toDecodedData()?.count, 32)
        XCTAssertNil(proof.jwk["d"])
        XCTAssertEqual(Set(proof.jwk.keys), ["kty", "crv", "x", "y"])
    }

    func test_proof_containsRequiredClaims() throws {
        let proof = try DecodedProof(makeDPoP(jti: { "jti-1" }).proof(method: "post", url: URL(string: "https://auth.example.com/oauth/token")!))

        XCTAssertEqual(proof.claims["jti"] as? String, "jti-1")
        XCTAssertEqual(proof.claims["htm"] as? String, "POST")
        XCTAssertEqual(proof.claims["htu"] as? String, "https://auth.example.com/oauth/token")
        XCTAssertEqual(proof.claims["iat"] as? Int, 1_700_000_000)
        XCTAssertNil(proof.claims["nonce"])
        XCTAssertNil(proof.claims["ath"])
    }

    func test_proof_signatureIsRawES256VerifiableWithEmbeddedJwk() throws {
        let proof = try DecodedProof(makeDPoP().proof(method: "POST", url: URL(string: "https://auth.example.com/oauth/token")!))

        XCTAssertEqual(proof.signature.count, 64)
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: proof.signature)
        XCTAssertTrue(try proof.publicKey().isValidSignature(signature, for: proof.signingInput))
    }

    func test_proof_segmentsAreBase64UrlWithoutPadding() throws {
        let jwt = try makeDPoP().proof(method: "POST", url: URL(string: "https://auth.example.com/oauth/token")!)
        XCTAssertFalse(jwt.contains("="))
        XCTAssertFalse(jwt.contains("+"))
        XCTAssertFalse(jwt.contains("/"))
    }

    func test_proof_includesNonceAndAthWhenProvided() throws {
        let proof = try DecodedProof(makeDPoP().proof(
            method: "GET",
            url: URL(string: "https://api.example.com/resource")!,
            accessToken: "Kz~8mXK1EalYznwH-LC-1fBAo.4Ljp~zsPE_NeO.gxU",
            nonce: "server-nonce"
        ))

        XCTAssertEqual(proof.claims["nonce"] as? String, "server-nonce")
        XCTAssertEqual(proof.claims["ath"] as? String, "fUHyO2r2Z3DZ53EsNrWBb0xWXoaNy59IiKCAqksmQEo")
    }

    func test_ath_matchesRfc9449Example() {
        XCTAssertEqual(
            FronteggDPoP.accessTokenHash("Kz~8mXK1EalYznwH-LC-1fBAo.4Ljp~zsPE_NeO.gxU"),
            "fUHyO2r2Z3DZ53EsNrWBb0xWXoaNy59IiKCAqksmQEo"
        )
    }

    func test_htu_dropsQueryAndFragmentAndNormalizesSchemeHostAndDefaultPort() {
        XCTAssertEqual(
            FronteggDPoP.htu(for: URL(string: "HTTPS://Auth.Example.COM:443/oauth/token?grant_type=x#frag")!),
            "https://auth.example.com/oauth/token"
        )
        XCTAssertEqual(
            FronteggDPoP.htu(for: URL(string: "https://auth.example.com:8443/path/To?q=1")!),
            "https://auth.example.com:8443/path/To"
        )
        XCTAssertEqual(
            FronteggDPoP.htu(for: URL(string: "https://user:pass@auth.example.com")!),
            "https://auth.example.com/"
        )
    }

    func test_jti_isUniquePerProof() throws {
        let dpop = makeDPoP()
        let url = URL(string: "https://auth.example.com/oauth/token")!
        let jtis = try (0..<50).map { _ in try DecodedProof(dpop.proof(method: "POST", url: url)).claims["jti"] as? String }

        XCTAssertEqual(Set(jtis.compactMap { $0 }).count, 50)
    }

    func test_key_isStableAcrossInstancesSharingStorage() throws {
        let url = URL(string: "https://auth.example.com/oauth/token")!
        let first = try DecodedProof(makeDPoP().proof(method: "POST", url: url))
        let second = try DecodedProof(makeDPoP().proof(method: "POST", url: url))

        XCTAssertEqual(first.jwk, second.jwk)
        XCTAssertNotNil(keyStorage.value)
    }

    func test_rotateKey_replacesKey() throws {
        let dpop = makeDPoP()
        let url = URL(string: "https://auth.example.com/oauth/token")!
        let before = try DecodedProof(dpop.proof(method: "POST", url: url))

        dpop.rotateKey()
        XCTAssertNil(keyStorage.value)

        let after = try DecodedProof(dpop.proof(method: "POST", url: url))
        XCTAssertNotEqual(before.jwk, after.jwk)
    }

    func test_key_isRegeneratedWhenStorageWasClearedExternally() throws {
        let dpop = makeDPoP()
        let url = URL(string: "https://auth.example.com/oauth/token")!
        let before = try DecodedProof(dpop.proof(method: "POST", url: url))

        keyStorage.value = nil

        let after = try DecodedProof(dpop.proof(method: "POST", url: url))
        XCTAssertNotEqual(before.jwk, after.jwk)
    }

    func test_key_isRegeneratedWhenStoredValueIsCorrupt() throws {
        keyStorage.value = "sw:not-a-key"
        let proof = try DecodedProof(makeDPoP().proof(method: "POST", url: URL(string: "https://auth.example.com/oauth/token")!))

        let signature = try P256.Signing.ECDSASignature(rawRepresentation: proof.signature)
        XCTAssertTrue(try proof.publicKey().isValidSignature(signature, for: proof.signingInput))
        XCTAssertNotEqual(keyStorage.value, "sw:not-a-key")
    }

    func test_thumbprint_isRfc7638OfPublicJwk() throws {
        let dpop = makeDPoP()
        let jwk = dpop.publicJWK()
        let canonical = "{\"crv\":\"P-256\",\"kty\":\"EC\",\"x\":\"\(jwk["x"]!)\",\"y\":\"\(jwk["y"]!)\"}"
        let expected = Data(SHA256.hash(data: Data(canonical.utf8))).toEncodedBase64()

        XCTAssertEqual(dpop.thumbprint(), expected)
    }

    func test_authorizationHeaders_useDPoPSchemeAndBindAccessToken() throws {
        let headers = try makeDPoP().authorizationHeaders(
            method: "GET",
            url: URL(string: "https://api.example.com/items?page=2")!,
            accessToken: "access-token"
        )

        XCTAssertEqual(headers["Authorization"], "DPoP access-token")
        let proof = try DecodedProof(XCTUnwrap(headers["DPoP"]))
        XCTAssertEqual(proof.claims["htm"] as? String, "GET")
        XCTAssertEqual(proof.claims["htu"] as? String, "https://api.example.com/items")
        XCTAssertEqual(proof.claims["ath"] as? String, FronteggDPoP.accessTokenHash("access-token"))
    }

    func test_authorizationHeaders_includeCachedNonceForOrigin() throws {
        let dpop = makeDPoP()
        dpop.recordNonce("rs-nonce", for: URL(string: "https://api.example.com/other")!)

        let headers = try dpop.authorizationHeaders(
            method: "GET",
            url: URL(string: "https://api.example.com/items")!,
            accessToken: "access-token"
        )
        let proof = try DecodedProof(XCTUnwrap(headers["DPoP"]))
        XCTAssertEqual(proof.claims["nonce"] as? String, "rs-nonce")

        let otherOrigin = try dpop.authorizationHeaders(
            method: "GET",
            url: URL(string: "https://other.example.com/items")!,
            accessToken: "access-token"
        )
        XCTAssertNil(try DecodedProof(XCTUnwrap(otherOrigin["DPoP"])).claims["nonce"])
    }

    func test_isNonceChallenge_detectsUseDPoPNonceError() {
        let url = URL(string: "https://auth.example.com/oauth/token")!
        let challenge = HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil, headerFields: ["DPoP-Nonce": "n"])!
        let body = Data(#"{"error":"use_dpop_nonce","error_description":"nonce required"}"#.utf8)

        XCTAssertTrue(FronteggDPoP.isNonceChallenge(challenge, data: body))
        XCTAssertFalse(FronteggDPoP.isNonceChallenge(challenge, data: Data(#"{"error":"invalid_grant"}"#.utf8)))

        let resourceChallenge = HTTPURLResponse(
            url: url,
            statusCode: 401,
            httpVersion: nil,
            headerFields: ["WWW-Authenticate": #"DPoP error="use_dpop_nonce", error_description="nonce""#, "DPoP-Nonce": "n"]
        )!
        XCTAssertTrue(FronteggDPoP.isNonceChallenge(resourceChallenge, data: Data()))

        let noNonceHeader = HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil, headerFields: nil)!
        XCTAssertFalse(FronteggDPoP.isNonceChallenge(noNonceHeader, data: body))
    }
}

// MARK: - Plist flag

final class DPoPPlistTests: XCTestCase {

    private func decode(_ extra: [String: Any]) throws -> FronteggPlist {
        var dict: [String: Any] = ["baseUrl": "https://auth.example.com", "clientId": "client-id"]
        extra.forEach { dict[$0.key] = $0.value }
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        return try PlistHelper.decode(FronteggPlist.self, from: data, at: "test")
    }

    func test_enableDPoP_defaultsToFalse() throws {
        XCTAssertFalse(try decode([:]).enableDPoP)
    }

    func test_enableDPoP_isReadFromPlist() throws {
        XCTAssertTrue(try decode(["enableDPoP": true]).enableDPoP)
    }
}

// MARK: - Api integration

private final class DPoPTransportApi: Api {
    struct Stub {
        let statusCode: Int
        let headers: [String: String]
        let body: String
    }

    var stubs: [Stub] = []
    private(set) var requests: [URLRequest] = []

    init(dpop: FronteggDPoP?) {
        super.init(baseUrl: "https://test.example.com", clientId: "test-client", applicationId: nil, dpop: dpop)
    }

    override func performData(for request: URLRequest, timeout: Int, followRedirect: Bool) async throws -> (Data, URLResponse) {
        requests.append(request)
        let stub = stubs.isEmpty ? Stub(statusCode: 200, headers: [:], body: DPoPTransportApi.tokenBody) : stubs.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.statusCode, httpVersion: nil, headerFields: stub.headers)!
        return (Data(stub.body.utf8), response)
    }

    override func addHttpBreadcrumb(
        method: String,
        url: URL?,
        statusCode: Int?,
        traceId: String?,
        durationMs: Int?,
        requestBodySize: Int?,
        responseBodySize: Int?,
        followRedirect: Bool,
        error: Error? = nil
    ) {}

    static let tokenBody = #"{"token_type":"DPoP","access_token":"a","refresh_token":"r","id_token":"i"}"#
    static let nonceChallengeBody = #"{"error":"use_dpop_nonce","error_description":"Authorization server requires nonce in DPoP proof"}"#
}

final class DPoPApiTests: XCTestCase {

    private var keyStorage: InMemoryDPoPKeyStorage!

    override func setUp() {
        super.setUp()
        keyStorage = InMemoryDPoPKeyStorage()
    }

    private func makeDPoP() -> FronteggDPoP {
        FronteggDPoP(storage: keyStorage.storage, preferSecureEnclave: false)
    }

    private func proofClaims(_ request: URLRequest) throws -> [String: Any] {
        try DecodedProof(XCTUnwrap(request.value(forHTTPHeaderField: "DPoP"))).claims
    }

    func test_flagOff_tokenEndpointRequestsCarryNoDPoPHeader() async throws {
        let api = DPoPTransportApi(dpop: nil)

        _ = await api.exchangeToken(code: "code", redirectUrl: "app://cb", codeVerifier: "v")
        _ = try await api.refreshToken(refreshToken: "rt")

        XCTAssertEqual(api.requests.count, 2)
        XCTAssertTrue(api.requests.allSatisfy { $0.value(forHTTPHeaderField: "DPoP") == nil })
    }

    func test_flagOff_apiBuiltFromDefaultConfigHasNoDPoP() {
        let api = Api(baseUrl: "https://test.example.com", clientId: "test-client", applicationId: nil)
        XCTAssertNil(api.dpop)
    }

    func test_authorizationCodeExchange_carriesProofForTokenEndpoint() async throws {
        let api = DPoPTransportApi(dpop: makeDPoP())

        let (response, error) = await api.exchangeToken(code: "code", redirectUrl: "app://cb", codeVerifier: "v")

        XCTAssertNil(error)
        XCTAssertEqual(response?.token_type, "DPoP")
        let request = try XCTUnwrap(api.requests.first)
        let claims = try proofClaims(request)
        XCTAssertEqual(claims["htm"] as? String, "POST")
        XCTAssertEqual(claims["htu"] as? String, "https://test.example.com/oauth/token")
        XCTAssertNil(claims["ath"])
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func test_oauthRefresh_carriesProof() async throws {
        let api = DPoPTransportApi(dpop: makeDPoP())

        _ = try await api.refreshToken(refreshToken: "rt")

        let claims = try proofClaims(XCTUnwrap(api.requests.first))
        XCTAssertEqual(claims["htu"] as? String, "https://test.example.com/oauth/token")
    }

    func test_silentAuthorizeWithToken_carriesProof() async throws {
        let api = DPoPTransportApi(dpop: makeDPoP())

        _ = try await api.silentAuthorizeWithToken(refreshToken: "rt")

        XCTAssertNotNil(api.requests.first?.value(forHTTPHeaderField: "DPoP"))
    }

    func test_identityTenantRefresh_doesNotCarryProof() async throws {
        let api = DPoPTransportApi(dpop: makeDPoP())

        _ = try await api.refreshToken(refreshToken: "rt", tenantId: "tenant-1", accessToken: "at")

        let request = try XCTUnwrap(api.requests.first)
        XCTAssertTrue(request.url!.path.hasSuffix("identity/resources/auth/v1/user/token/refresh"))
        XCTAssertNil(request.value(forHTTPHeaderField: "DPoP"))
    }

    func test_useDPoPNonceChallenge_retriesOnceWithServerNonce() async throws {
        let api = DPoPTransportApi(dpop: makeDPoP())
        api.stubs = [
            .init(statusCode: 400, headers: ["DPoP-Nonce": "nonce-1"], body: DPoPTransportApi.nonceChallengeBody),
            .init(statusCode: 200, headers: [:], body: DPoPTransportApi.tokenBody),
        ]

        let result = try await api.refreshToken(refreshToken: "rt")

        XCTAssertEqual(result.access_token, "a")
        XCTAssertEqual(api.requests.count, 2)
        XCTAssertNil(try proofClaims(api.requests[0])["nonce"])
        let retryClaims = try proofClaims(api.requests[1])
        XCTAssertEqual(retryClaims["nonce"] as? String, "nonce-1")
        XCTAssertNotEqual(retryClaims["jti"] as? String, try proofClaims(api.requests[0])["jti"] as? String)
    }

    func test_nonceFromPreviousResponse_isSentOnNextRequest() async throws {
        let api = DPoPTransportApi(dpop: makeDPoP())
        api.stubs = [
            .init(statusCode: 200, headers: ["DPoP-Nonce": "nonce-2"], body: DPoPTransportApi.tokenBody),
            .init(statusCode: 200, headers: [:], body: DPoPTransportApi.tokenBody),
        ]

        _ = try await api.refreshToken(refreshToken: "rt")
        _ = try await api.refreshToken(refreshToken: "rt")

        XCTAssertEqual(try proofClaims(api.requests[1])["nonce"] as? String, "nonce-2")
    }

    func test_repeatedNonceChallenge_retriesOnlyOnce() async throws {
        let api = DPoPTransportApi(dpop: makeDPoP())
        api.stubs = [
            .init(statusCode: 400, headers: ["DPoP-Nonce": "n1"], body: DPoPTransportApi.nonceChallengeBody),
            .init(statusCode: 400, headers: ["DPoP-Nonce": "n2"], body: DPoPTransportApi.nonceChallengeBody),
        ]

        do {
            _ = try await api.refreshToken(refreshToken: "rt")
            XCTFail("Expected refresh to fail")
        } catch {}

        XCTAssertEqual(api.requests.count, 2)
    }

    func test_nonNonceError_isNotRetried() async throws {
        let api = DPoPTransportApi(dpop: makeDPoP())
        api.stubs = [
            .init(statusCode: 400, headers: [:], body: #"{"errors":["DPoP proof key does not match the bound key"]}"#),
        ]

        do {
            _ = try await api.refreshToken(refreshToken: "rt")
            XCTFail("Expected refresh to fail")
        } catch {}

        XCTAssertEqual(api.requests.count, 1)
    }
}
