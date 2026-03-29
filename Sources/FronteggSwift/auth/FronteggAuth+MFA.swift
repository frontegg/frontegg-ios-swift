//
//  FronteggAuth+MFA.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import Foundation

extension FronteggAuth {

    func handleMfaRequired(_ _completion: FronteggAuth.CompletionHandler? = nil) -> FronteggAuth.CompletionHandler {
        let completion: FronteggAuth.CompletionHandler = { (result) in

            switch (result) {
            case .success(_):
                DispatchQueue.main.async {
                    FronteggAuth.shared.setIsLoading(false)
                    _completion?(result)
                }

            case .failure(let fronteggError):

                switch fronteggError {
                case .authError(let authError):
                    if case let .mfaRequired(jsonResponse, refreshToken) = authError {
                        self.logger.info("MFA required with JSON response: \(jsonResponse)")
                        self.startMultiFactorAuthenticator(
                            mfaRequestData: jsonResponse,
                            refreshToken: refreshToken,
                            completion: _completion
                        )

                        return
                    } else {
                        self.logger.info("authentication error: \(authError.localizedDescription)")
                    }
                case .configError(let configError):
                    self.logger.info("config error: \(configError.localizedDescription)")
                case .networkError(let error):
                    self.logger.info("network error: \(error.localizedDescription)")
                }

                DispatchQueue.main.async {
                    FronteggAuth.shared.setIsLoading(false)
                    _completion?(result)
                }
            }
        }
        return completion
    }

    func startMultiFactorAuthenticator(
        mfaRequestData: [String: Any]? = nil,
        mfaRequestJson: String? = nil,
        refreshToken: String? = nil,
        completion: FronteggAuth.CompletionHandler? = nil
    ) {
        Task {
            do {
                var authorizeUrl: URL

                if let requestData = mfaRequestData {
                    (authorizeUrl, _) = try await multiFactorAuthenticator.start(mfaRequestData: requestData, refreshToken: refreshToken)
                } else if let requestJson = mfaRequestJson {
                    (authorizeUrl, _) = try multiFactorAuthenticator.start(mfaRequestJson: requestJson)
                } else {
                    return
                }

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.setIsLoading(false)

                    if self.embeddedMode {
                        self.activeEmbeddedOAuthFlow = .mfa
                        self.pendingAppLink = authorizeUrl
                        self.setWebLoading(true)
                        self.embeddedLogin(completion, loginHint: nil)
                        return
                    }

                    let oauthCallback = self.createOauthCallbackHandler(
                        completion ?? { _ in },
                        pendingOAuthState: self.pendingOAuthState(from: authorizeUrl),
                        flow: .mfa
                    )
                    WebAuthenticator.shared.start(authorizeUrl, completionHandler: oauthCallback)
                }
            } catch let error as FronteggError {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.setIsLoading(false)
                }
                completion?(.failure(error))
            }
        }
    }
}
