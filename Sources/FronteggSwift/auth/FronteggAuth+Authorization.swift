//
//  FronteggAuth+Authorization.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import Foundation

extension FronteggAuth {

    /// Authorizes the session using a refresh token (and optional device token cookie).
    /// The refresh token must come from identity-server APIs, e.g. sign-up:
    /// `POST /frontegg/identity/resources/users/v1/signUp`.
    public func requestAuthorizeAsync(refreshToken: String, deviceTokenCookie: String? = nil) async throws -> User {
        FronteggAuth.shared.setIsLoading(true)

        self.logger.info("Requesting authorize with refresh and device tokens")

        do {
            let authResponse = try await self.api.authroizeWithTokens(refreshToken: refreshToken, deviceTokenCookie: deviceTokenCookie)
            await FronteggAuth.shared.setCredentials(accessToken: authResponse.access_token, refreshToken: authResponse.refresh_token)

            if let user = self.user {
                return user
            }

            throw FronteggError.authError(.failedToAuthenticate)
        } catch {
            self.logger.error("Authorization request failed: \(error.localizedDescription)")
            FronteggAuth.shared.setIsLoading(false)
            throw error
        }
    }

    /// Callback-based variant of `requestAuthorizeAsync`. Use with tokens from identity-server APIs
    /// (e.g. `POST /frontegg/identity/resources/users/v1/signUp`).
    public func requestAuthorize(refreshToken: String, deviceTokenCookie: String? = nil, _ completion: @escaping FronteggAuth.CompletionHandler) {
        DispatchQueue.global(qos: .userInitiated).async {
            Task {
                do {
                    let user = try await self.requestAuthorizeAsync(refreshToken: refreshToken, deviceTokenCookie: deviceTokenCookie)
                    await MainActor.run {
                        completion(.success(user))
                    }
                } catch let error as FronteggError {
                    await MainActor.run {
                        completion(.failure(error))
                    }
                } catch {
                    self.logger.error("Failed to authenticate: \(error.localizedDescription)")
                    await MainActor.run {
                        completion(.failure(.authError(.failedToAuthenticate)))
                    }
                }
            }
        }
    }
}
