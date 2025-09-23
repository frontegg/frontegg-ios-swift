import Foundation
import AuthenticationServices


// MARK: - Passkeys Authenticator Class

@available(iOS 15.0, *)
class PasskeysAuthenticator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    
    static let shared = PasskeysAuthenticator()
    
    private var callbackAction: ((_ data: WebAuthnCallbackData?, _ error: Error?) -> Void)?
    private var logger = getLogger("PasskeysAuthenticator")
    
    // MARK: - WebAuthn Registration
    
    func startWebAuthn(_ completion: FronteggAuth.ConditionCompletionHandler? = nil) {
        let baseUrl = FronteggAuth.shared.baseUrl
        
        if let completion = completion  {
            self.callbackAction = { (data, error) in
                if let regsitration = data as? WebauthnRegistration {
                    self.verifyNewDeviceSession(publicKey: regsitration)
                } else {
                    if error == nil {
                        completion(nil)
                    }else if let frotneggError = error as? FronteggError {
                        completion(frotneggError)
                    } else {
                        completion(FronteggError.authError(.unknown))
                    }
                }
            }
        }
        guard let url = URL(string: "\(baseUrl)/frontegg/identity/resources/users/webauthn/v1/devices"),
              let accessToken = FronteggAuth.shared.accessToken else {
            logger.error("Invalid base URL or missing access token")
            self.callbackAction?(nil, FronteggError.authError(.notAuthenticated))
            return
        }
        
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "authorization")
        request.setValue(baseUrl, forHTTPHeaderField: "origin")
        
        // Add body data here if necessary
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("Error fetching WebAuthn options: \(error.localizedDescription)")
                self.callbackAction?(nil, error)
                return
            }
            
            guard let data = data else {
                self.logger.error("No data received")
                self.callbackAction?(nil, FronteggError.authError(.invalidPasskeysRequest))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let options = json["options"] as? [String: Any] {
                    try self.createCredentialRegistrationRequest(with: options)
                } else {
                    self.logger.error("Invalid JSON structure in response")
                    self.callbackAction?(nil, FronteggError.authError(.invalidPasskeysRequest))
                }
            } catch {
                self.logger.error("Error parsing JSON: \(error.localizedDescription)")
                self.callbackAction?(nil, error)
            }
        }
        
        task.resume()
    }
    
    // MARK: - Credential Registration
    
    func createCredentialRegistrationRequest(with options: [String: Any]) throws {
        guard let challenge = options["challenge"] as? String,
              let user = options["user"] as? [String: Any],
              let rp = options["rp"] as? [String: Any],
              let rpId = rp["id"] as? String,
              let name = user["name"] as? String,
              let userIdString = user["id"] as? String,
              let userIdData = base64UrlDecode(userIdString),
              let challengeData = base64UrlDecode(challenge) else {
            throw FronteggError.authError(.invalidPasskeysRequest)
        }
        
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)
        let registrationRequest = provider.createCredentialRegistrationRequest(
            challenge: challengeData,
            name: name,
            userID: userIdData
        )
        
        let authController = ASAuthorizationController(authorizationRequests: [registrationRequest])
        authController.delegate = self
        authController.presentationContextProvider = self
        authController.performRequests()
    }
    
    // MARK: - ASAuthorizationControllerDelegate Methods
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration {
            handleRegistrationSuccess(credential: credential)
        } else if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
            handleAssertionSuccess(credential: credential)
        } else {
            let error = FronteggError.authError(.invalidPasskeysRequest)
            self.callbackAction?(nil, error)
        }
        
        self.callbackAction = nil
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        
        self.callbackAction?(nil, error)
        self.callbackAction = nil
    }
    
    // MARK: - Credential Handling
    
    private func handleRegistrationSuccess(credential: ASAuthorizationPlatformPublicKeyCredentialRegistration) {
        let regsitration = WebauthnRegistration(credential: credential)
        if let callback = self.callbackAction {
            callback(regsitration, nil)
        } else {
            self.verifyNewDeviceSession(publicKey: regsitration)
        }
    }
    
    private func handleAssertionSuccess(credential: ASAuthorizationPlatformPublicKeyCredentialAssertion) {
        
        let creds = WebauthnAssertion(credential: credential)
        
        
        if let callback = self.callbackAction {
            callback(creds, nil)
        }
    }
    
    // MARK: - ASAuthorizationControllerPresentationContextProviding
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return UIApplication.shared.windows.first ?? UIWindow()
    }
    
    
    
    // Helper function to wrap the callback-based API
    func performCredentialAssertionRequest(challenge: Data, rpId: String) async throws -> WebauthnAssertion {
        return try await withCheckedThrowingContinuation { continuation in
            // Set up the callback to resume the continuation
            self.callbackAction = { data, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data {
                    continuation.resume(returning: data as! WebauthnAssertion)
                } else {
                    continuation.resume(throwing: FronteggError.authError(.invalidPasskeysRequest))
                }
            }
            
            // Call the method that triggers the credential assertion request
            getCredentialAssertionRequest(challenge, rpId: rpId)
        }
    }
    // MARK: - Passkeys Login
    func loginWithPasskeys(_ completion: FronteggAuth.CompletionHandler? = nil, _ retries: Int = 3) async {
        do {
    
            DispatchQueue.main.async {
                FronteggAuth.shared.setIsLoading(true)
            }
            
            let prelogin = try await FronteggAuth.shared.api.preloginWebauthn()
                    
            // Await the challenge response from the credential assertion request
            let assertion = try await performCredentialAssertionRequest(challenge: prelogin.challenge, rpId: prelogin.rpId)
            
            
            let authResponse = try await FronteggAuth.shared.api.postloginWebauthn(assertion: assertion)
            
            await FronteggAuth.shared.setCredentials(accessToken: authResponse.access_token, refreshToken: authResponse.refresh_token)
            
            
        } catch {
            if let fronteggError = error as? FronteggError {
                completion?(.failure(fronteggError))
            }else {
                
                if let m = error as? AuthenticationServices.ASAuthorizationError,
                   m.errorCode == 1004,
                   retries > 0 {
                    logger.error("Retrying loginWithPasskeys due to error: \(error.localizedDescription)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
                        Task{
                            await self.loginWithPasskeys(completion, retries - 1)
                        }
                    })
                }else {
                    logger.error("Error during loginWithPasskeys: \(error.localizedDescription)")
                    
                    DispatchQueue.main.async {
                        FronteggAuth.shared.setIsLoading(false)
                    }
                    completion?(.failure(.authError(.failedToAuthenticate)))
                }
            }
        }
    }
    
    // MARK: - Credential Assertion Request
    
    private func getCredentialAssertionRequest(_ challengeData: Data, rpId: String) {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)
        let assertionRequest = provider.createCredentialAssertionRequest(challenge: challengeData)
        
        let authController = ASAuthorizationController(authorizationRequests: [assertionRequest])
        authController.delegate = self
        authController.presentationContextProvider = self
        authController.performRequests()
    }
    
    // MARK: - Verify New Device Session
    
    private func verifyNewDeviceSession(publicKey: WebauthnRegistration) {
        let baseUrl = FronteggAuth.shared.baseUrl
        
        guard let url = URL(string: "\(baseUrl)/frontegg/identity/resources/users/webauthn/v1/devices/verify"),
              let accessToken = FronteggAuth.shared.accessToken else {
            logger.error("Invalid base URL or missing access token")
            
            self.callbackAction?(nil, FronteggError.authError(.unknown))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "authorization")
        request.setValue(baseUrl, forHTTPHeaderField: "origin")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: publicKey.toDictionary())
            request.httpBody = jsonData
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    self.logger.error("Error verifying new device session: \(error.localizedDescription)")
                    self.callbackAction?(nil, error)
                    return
                }
                
                guard let data = data else {
                    self.logger.error("No data received")
                    self.callbackAction?(nil, FronteggError.authError(.invalidPasskeysRequest))
                    return
                }
                
                do {
                    
                    if let dataStr = String(data:data, encoding: .utf8),
                       let httpResponse = response as? HTTPURLResponse,
                       dataStr.isEmpty, httpResponse.statusCode < 300 {
                        self.logger.debug("Response from verify succeeded with empty body")
                        self.callbackAction?(nil, nil)
                    }else {
                        
                        if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            self.logger.debug("Response from verify endpoint: \(jsonResponse)")
                            self.callbackAction?(jsonResponse, nil)
                        } else {
                            self.logger.error("Invalid JSON structure in response")
                            self.callbackAction?(nil, FronteggError.authError(.invalidPasskeysRequest))
                        }
                    }
                } catch {
                    self.logger.error("Error parsing JSON: \(error.localizedDescription)")
                    self.callbackAction?(nil, error)
                }
            }
            
            task.resume()
        } catch {
            logger.error("Failed to serialize request body: \(error.localizedDescription)")
            self.callbackAction?(nil, error)
        }
    }
    
    // MARK: - Handle Hosted Login Request
    
    func handleHostedLoginRequest(_ message: HostedLoginMessage, callback: @escaping (_ data: WebAuthnCallbackData?, _ error: Error?) -> Void) throws {
        guard let jsonData = message.payload.data(using: .utf8) else {
            throw FronteggError.authError(.invalidPasskeysRequest)
        }
        
        if message.action == "getPasskey" {
            let request = try JSONDecoder().decode(GetPasskeysRequest.self, from: jsonData)
            guard let challengeData = base64UrlDecode(request.publicKey.challenge) else {
                throw FronteggError.authError(.invalidPasskeysRequest)
            }
            self.callbackAction = callback
            getCredentialAssertionRequest(challengeData, rpId: request.publicKey.rpId)
        } else if message.action == "createPasskey" {
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData)
            guard let dictionary = jsonObject as? [String: Any],
                  let publicKey = dictionary["publicKey"] as? [String: Any] else {
                throw FronteggError.authError(.invalidPasskeysRequest)
            }
            self.callbackAction = callback
            try createCredentialRegistrationRequest(with: publicKey)
        } else {
            throw FronteggError.authError(.invalidPasskeysRequest)
        }
    }
    
    // MARK: - Helper Methods
    
    private func base64UrlDecode(_ input: String) -> Data? {
        var base64 = input.replacingOccurrences(of: "-", with: "+")
                         .replacingOccurrences(of: "_", with: "/")
        let paddingLength = 4 - (base64.count % 4)
        if paddingLength < 4 {
            base64 += String(repeating: "=", count: paddingLength)
        }
        return Data(base64Encoded: base64)
    }
    
    private func base64UrlEncode(_ inputData: Data?) -> String {
        guard let inputData = inputData else { return "" }
        var base64 = inputData.base64EncodedString()
        base64 = base64.replacingOccurrences(of: "+", with: "-")
                       .replacingOccurrences(of: "/", with: "_")
                       .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        return base64
    }
    
    // MARK: - JavaScript Hook for iOS 15 Passkeys
    
public static let ios15PasskeysHook = """

window.navigator.credentials = {
  helpers: {
    listeners: new Map(),
    chars: 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_',
    base64urlEncode: (arraybuffer) => {
      const chars = window.navigator.credentials.helpers.chars;
      const bytes = new Uint8Array(arraybuffer);
      const len = bytes.length;
      let base64url = '';

      for (let i = 0; i < len; i += 3) {
        base64url += chars[bytes[i] >> 2];
        base64url += chars[((bytes[i] & 3) << 4) | (bytes[i + 1] >> 4)];
        base64url += chars[((bytes[i + 1] & 15) << 2) | (bytes[i + 2] >> 6)];
        base64url += chars[bytes[i + 2] & 63];
      }

      if (len % 3 === 2) {
        base64url = base64url.substring(0, base64url.length - 1);
      } else if (len % 3 === 1) {
        base64url = base64url.substring(0, base64url.length - 2);
      }

      return base64url;
    },
    base64urlDecode: (base64string) => {
      const chars = window.navigator.credentials.helpers.chars;
      const lookup = new Uint8Array(256);

      // Initialize lookup array
      for (let i = 0; i < chars.length; i++) {
        lookup[chars.charCodeAt(i)] = i;
      }
      const bufferLength = base64string.length * 0.75;
      const len = base64string.length;
      let p = 0;
      let encoded1, encoded2, encoded3, encoded4;

      const bytes = new Uint8Array(bufferLength);

      for (let i = 0; i < len; i += 4) {
        encoded1 = lookup[base64string.charCodeAt(i)];
        encoded2 = lookup[base64string.charCodeAt(i + 1)];
        encoded3 = lookup[base64string.charCodeAt(i + 2)];
        encoded4 = lookup[base64string.charCodeAt(i + 3)];

        bytes[p++] = (encoded1 << 2) | (encoded2 >> 4);
        bytes[p++] = ((encoded2 & 15) << 4) | (encoded3 >> 2);
        bytes[p++] = ((encoded3 & 3) << 6) | (encoded4 & 63);
      }

      return bytes.buffer;
    },
  },

  create: (options) => {
    return new Promise((resolve, reject) => {
      const challenge = window.navigator.credentials.helpers.base64urlEncode(options.publicKey.challenge);
      const userId = window.navigator.credentials.helpers.base64urlEncode(options.publicKey.user.id);
                
      const callbackId = Math.random().toString(36).substring(7);
      window.navigator.credentials.helpers.listeners.set(callbackId, { resolve: (data) => {
        resolve({
            ...data,

        })
      }, reject });
      window.webkit?.messageHandlers?.FronteggNativeBridge?.postMessage(
        JSON.stringify({
          action: 'createPasskey',
          callbackId,
          payload: JSON.stringify({
            ...options,
            publicKey: {
              ...options.publicKey,
              challenge,
              user: {
                ...options.publicKey.user,
                id: userId
              }
            },
          }),
        }),
      );
    });
  },
  get: (options) => {
    return new Promise((resolve, reject) => {
      const challenge = window.navigator.credentials.helpers.base64urlEncode(options.publicKey.challenge);
      console.log("challenge", challenge)
      const callbackId = Math.random().toString(36).substring(7);
        window.navigator.credentials.helpers.listeners.set(callbackId, { resolve: (data) => {
          const base64urlDecode = window.navigator.credentials.helpers.base64urlDecode
          resolve({
              ...data,
              rawId: base64urlDecode(data.rawId),
              response: {
                authenticatorData: base64urlDecode(data.response.authenticatorData),
                clientDataJSON: base64urlDecode(data.response.clientDataJSON),
                signature: base64urlDecode(data.response.signature),
                userHandle: base64urlDecode(data.response.userHandle),
              }
          })
        }, reject });
      window.webkit?.messageHandlers?.FronteggNativeBridge?.postMessage(
        JSON.stringify({
          action: 'getPasskey',
          callbackId,
          payload: JSON.stringify({
            ...options,
            publicKey: {
              ...options.publicKey,
              challenge,
            },
          }),
        }),
      );
    });
  },
};


"""
    
}
