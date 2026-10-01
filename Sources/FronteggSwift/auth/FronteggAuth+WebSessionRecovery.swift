//
//  FronteggAuth+WebSessionRecovery.swift
//  FronteggSwift
//
//  Re-establishes a session from the login box's web session when the native refresh token is rejected.
//

import Foundation

extension FronteggAuth {

    /// Returns true when new credentials were issued for the same user from the login web session.
    func recoverSessionFromWebSession() async -> Bool {
        guard embeddedMode else { return false }
        guard let host = URL(string: baseUrl)?.host,
              let cookie = await webSessionCookies.refreshCookie(for: host) else {
            logger.info("Web session recovery skipped: no login web session cookie")
            return false
        }

        let previousSubject = currentSubject()
        do {
            let (authResponse, responseCookies) = try await api.authorizeWithWebSession(cookie: cookie)
            let recoveredSubject = (try? JWTHelper.decode(jwtToken: authResponse.access_token))?["sub"] as? String
            if let previousSubject, recoveredSubject != previousSubject {
                logger.warning("Web session recovery rejected: the web session belongs to a different user")
                return false
            }
            await webSessionCookies.store(responseCookies)
            await setCredentials(accessToken: authResponse.access_token, refreshToken: authResponse.refresh_token)
            let recovered = await MainActor.run { self.isAuthenticated }
            logger.info("Session recovery from the login web session \(recovered ? "succeeded" : "failed")")
            return recovered
        } catch {
            logger.warning("Web session recovery failed: \(error.localizedDescription)")
            return false
        }
    }

    private func currentSubject() -> String? {
        let accessToken = self.accessToken ?? (try? credentialManager.get(key: KeychainKeys.accessToken.rawValue))
        if let accessToken, let subject = (try? JWTHelper.decode(jwtToken: accessToken))?["sub"] as? String {
            return subject
        }
        return user?.id
    }
}
