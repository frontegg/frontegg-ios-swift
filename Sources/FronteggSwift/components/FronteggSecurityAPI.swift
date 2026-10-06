//
//  FronteggSecurityAPI.swift
//  FronteggSwift
//

import Foundation

struct FronteggSecurityAPI {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    static let sessionsPath = "/frontegg/identity/resources/users/sessions/v1/me"
    static let webAuthnDevicesPath = "/frontegg/identity/resources/users/webauthn/v1/devices"

    private static let pathSegmentAllowed: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        return allowed
    }()

    let baseUrl: String
    let applicationId: String?
    let accessTokenProvider: () async throws -> String?
    let transport: Transport
    var timeout: TimeInterval = TimeInterval(Api.DEFAULT_TIMEOUT)

    static let urlSessionTransport: Transport = { request in
        try await URLSession.shared.data(for: request)
    }

    static func sessionId(fromAccessToken accessToken: String) -> String? {
        guard let claims = try? JWTHelper.decode(jwtToken: accessToken) else { return nil }
        return claims["sid"] as? String
    }

    func listSessions() async throws -> [FronteggSession] {
        let (data, accessToken) = try await send("GET", path: Self.sessionsPath)
        guard let sessions = try? JSONDecoder().decode([SessionDTO].self, from: data) else {
            throw FronteggSecurityCenterError.invalidResponse
        }
        let currentSessionId = Self.sessionId(fromAccessToken: accessToken)
        return sessions.map { dto in
            let session = dto.model
            return session.markingCurrent(session.isCurrent || session.id == currentSessionId)
        }
    }

    func revokeSession(id: String) async throws {
        _ = try await send("DELETE", path: "\(Self.sessionsPath)/\(Self.encode(id))")
    }

    func revokeOtherSessions() async throws {
        _ = try await send("DELETE", path: "\(Self.sessionsPath)/all")
    }

    func listPasskeys() async throws -> [FronteggPasskey] {
        let (data, _) = try await send("GET", path: Self.webAuthnDevicesPath)
        guard let response = try? JSONDecoder().decode(WebAuthnDevicesDTO.self, from: data) else {
            throw FronteggSecurityCenterError.invalidResponse
        }
        return response.models
    }

    func deletePasskey(id: String) async throws {
        _ = try await send("DELETE", path: "\(Self.webAuthnDevicesPath)/\(Self.encode(id))")
    }

    private static func encode(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed) ?? segment
    }

    private func send(_ method: String, path: String) async throws -> (Data, String) {
        guard let accessToken = try await accessTokenProvider(), !accessToken.isEmpty else {
            throw FronteggSecurityCenterError.notAuthenticated
        }
        guard let url = URL(string: "\(baseUrl)\(path)") else {
            throw ApiError.invalidUrl("invalid url: \(baseUrl)\(path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(baseUrl, forHTTPHeaderField: "Origin")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let applicationId {
            request.setValue(applicationId, forHTTPHeaderField: "frontegg-requested-application-id")
        }

        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse else {
            throw FronteggSecurityCenterError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw FronteggSecurityCenterError.requestFailed(statusCode: http.statusCode)
        }
        return (data, accessToken)
    }
}
