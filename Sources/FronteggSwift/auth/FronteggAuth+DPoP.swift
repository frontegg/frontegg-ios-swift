//
//  FronteggAuth+DPoP.swift
//

import Foundation

extension FronteggAuth {

    /// True when `enableDPoP` is set in Frontegg.plist.
    public var isDPoPEnabled: Bool {
        api.dpop != nil
    }

    /// The DPoP proof generator, or nil when DPoP is disabled.
    public var dpop: FronteggDPoP? {
        api.dpop
    }

    /// Returns a DPoP proof JWT for a request to `url`, bound to the current access token (`ath`).
    public func dpopProof(method: String, url: URL) throws -> String {
        guard let dpop = api.dpop else { throw FronteggDPoPError.disabled }
        guard let accessToken = self.accessToken else { throw FronteggDPoPError.missingAccessToken }
        return try dpop.proof(method: method, url: url, accessToken: accessToken, nonce: dpop.nonce(for: url))
    }

    /// Returns `Authorization: DPoP <access token>` and `DPoP: <proof>` headers for a request to your resource server.
    public func dpopAuthorizationHeaders(method: String, url: URL) throws -> [String: String] {
        guard let dpop = api.dpop else { throw FronteggDPoPError.disabled }
        guard let accessToken = self.accessToken else { throw FronteggDPoPError.missingAccessToken }
        return try dpop.authorizationHeaders(method: method, url: url, accessToken: accessToken)
    }

    /// Adds DPoP `Authorization` and `DPoP` headers to `request`, using its URL and HTTP method.
    public func applyDPoP(to request: inout URLRequest) throws {
        guard let url = request.url else { throw URLError(.badURL) }
        let headers = try dpopAuthorizationHeaders(method: request.httpMethod ?? "GET", url: url)
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
    }
}
