//
//  File.swift
//  
//
//  Created by David Antoon on 15/10/2024.
//

import Foundation
import AuthenticationServices



struct GetPasskeysRequest: Codable {
    
    struct PublicKeyCredential: Codable {
        var timeout: Int
        var rpId: String
        var userVerification: String
        var challenge: String
    }
    var publicKey: PublicKeyCredential
}

struct CreatePasskeysRequest: Codable {
    struct PublicKeyCredential: Codable {
        struct Rp: Codable {
            let name: String
            let id: String
        }

        struct User: Codable {
            let id: [String: String] // Assuming it's a dictionary, as it appears empty in the provided JSON.
            let name: String
            let displayName: String
        }

        struct PubKeyCredParam: Codable {
            let type: String
            let alg: Int
        }

        struct AuthenticatorSelection: Codable {
            let userVerification: String
        }

        let rp: Rp
        let user: User
        let challenge: String
        let pubKeyCredParams: [PubKeyCredParam]
        let timeout: Int
        let attestation: String
        let authenticatorSelection: AuthenticatorSelection
        let excludeCredentials: [String] // Assuming it's an empty array for now
    }
    
    var publicKey: PublicKeyCredential
}

// Coordinator to handle ASAuthorizationController delegation
@available(iOS 15.0, *)
class PasskeysAuthenticator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {

    public static let shared = PasskeysAuthenticator()

    
    private var callbackAction: ((_ data:[String: Any]?, _ error: Error?)-> Void)? = nil
    private var logger = getLogger("PasskeysAuthenticator")
    func startWebAuthn() {
        
        let baseUrl = FronteggAuth.shared.baseUrl
        // 1. Create New Device Session (request options)
        guard let url = URL(string: "\(baseUrl)/frontegg/identity/resources/users/webauthn/v1/devices") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(FronteggAuth.shared.accessToken ?? "")", forHTTPHeaderField: "authorization")
        request.setValue(baseUrl, forHTTPHeaderField: "origin")
        
        // You may need to add body data here for user identification
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                print("Error fetching WebAuthn options: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            // Parse the response and get the WebAuthn options
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let options = json["options"] as? [String: Any] {
                // Proceed with WebAuthn registration using the options from the server
                try? self.createCredentialRegistrationRequest(with: options)
            }
        }
        
        task.resume()
    }

    // This function handles the WebAuthn creation request
    func createCredentialRegistrationRequest(with options: [String: Any]) throws -> Void {
        guard let challenge = options["challenge"] as? String,
              let user = options["user"] as? [String: Any],
              let rp = options["rp"] as? [String: String],
              let rpId = rp["id"],
              let name = user["name"] as? String,
              let userIdData = base64UrlDecode(user["id"] as! String),
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

    
    // Delegate method for successful WebAuthn registration
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration {
            let attestationObject = credential.rawAttestationObject
            let clientDataJSON = credential.rawClientDataJSON
            let credentialID = credential.credentialID
            let publicKey = [
                "id": base64UrlEncode(credentialID),
                "response": [
                    "clientDataJSON": base64UrlEncode(clientDataJSON),
                    "attestationObject": base64UrlEncode(attestationObject)
                ],
                "authenticatorAttachment": "platform"
            ] as [String : Any]
            
            if let callback = self.callbackAction {
                
                
                callback(publicKey, nil)
                
            } else {
//                // Send the publicKey and result to verify on the backend
//                let publicKey = [
//                    "id": credentialID.base64EncodedString(),
//                    "response": [
//                        "clientDataJSON": clientDataJSON.base64EncodedString(),
//                        "attestationObject": attestationObject?.base64EncodedString()
//                    ],
//                    "authenticatorAttachment": "platform"
//                ] as [String : Any]
//                
                verifyNewDeviceSession(publicKey: publicKey)
            }
        }
        
        if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
            let clientDataJSON = credential.rawClientDataJSON
            let authenticatorData = credential.rawAuthenticatorData
            let signature = credential.signature
            let credentialID = credential.credentialID
            let userHandle = credential.userID

            let publicKey = [
                "id": base64UrlEncode(credentialID),
                "rawId": base64UrlEncode(credentialID),
                "response": [
                    "clientDataJSON": base64UrlEncode(clientDataJSON),
                    "authenticatorData": base64UrlEncode(authenticatorData),
                    "signature": base64UrlEncode(signature),
                    "userHandle": base64UrlEncode(userHandle)
                ],
                "authenticatorAttachment": "platform",
                "type": "public-key"
            ] as [String : Any]
            
            if let callback = self.callbackAction {
                // Send the publicKey and result to verify on the backend
                callback(publicKey, nil)
            } else {
                
                //verifyPassekeysSession(publicKey: publicKey)
            }
        }
        
        self.callbackAction = nil
    }
    
    func loginWithPasskeys() async {
        _ = FronteggAuth.shared.baseUrl
        // 1. Create New Device Session (request options)
        
        do {
            let (preloginResponse, _) = try await FronteggAuth.shared.api.postRequest(path: "frontegg/identity/resources/auth/v1/webauthn/prelogin", body: [:])
            
            guard
                let preloginChallenge = try JSONSerialization.jsonObject(with: preloginResponse, options: [])  as? [String: Any],
                let options = preloginChallenge["options"] as? [String: Any],
                  let challenge = options["challenge"] as? String,
                  let rpId = options["rpId"] as? String,
                  let challengeData = base64UrlDecode(challenge) else {
                throw FronteggError.authError(.invalidPasskeysRequest)
            }
            
            
            self.callbackAction = { (data, error) in
                if let challengeResponse = data {
                
                    Task {
                        
                        let (postloginResponse, response) = try await FronteggAuth.shared.api.postRequest(path: "frontegg/identity/resources/auth/v1/webauthn/postlogin", body: challengeResponse)
                        if let res = response as? HTTPURLResponse, res.statusCode != 401 {
                            
                            if let postLoginData = try JSONSerialization.jsonObject(with: postloginResponse, options: [])  as? [String: Any],
                                let accesstoken = postLoginData["accessToken"] as? String,
                                let refreshToken = FronteggAuth.shared.api.getRefreshTokenFromHeaders(response:res) {
                                
                                await FronteggApp.shared.auth.setCredentials(accessToken:accesstoken , refreshToken: refreshToken)
                            }
                        }
                    }
                }
                
            }
            getCredentialAssertionRequest(challengeData, rpId: rpId)
            
        }catch {
            
        }
    }
    
    // Delegate method for failed WebAuthn session
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        print("Error during WebAuthn session: \(error.localizedDescription)")
    }
    
    // Required for presentation context in SwiftUI
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return UIApplication.shared.windows.first ?? UIWindow()
    }

    // 2. Verify New Device Session
    func verifyNewDeviceSession(publicKey: [String: Any]) {
        let baseUrl = FronteggAuth.shared.baseUrl
        guard let url = URL(string: "\(baseUrl)/frontegg/identity/resources/users/webauthn/v1/devices/verify") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(FronteggAuth.shared.accessToken ?? "")", forHTTPHeaderField: "authorization")
        request.setValue(baseUrl, forHTTPHeaderField: "origin")
        
        let deviceType = publicKey["authenticatorAttachment"] as? String == "platform" ? "Platform" : "CrossPlatform"
        var requestBody = publicKey
        requestBody["deviceType"] = deviceType
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            request.httpBody = jsonData
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("Error: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else {
                    print("No data received")
                    return
                }
                
                // Handle the response from the server
                if let jsonResponse = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    print("Response from verify endpoint: \(jsonResponse)")
                    // Handle the success or failure based on server response
                }
            }
            
            task.resume()
        } catch {
            print("Failed to serialize request body: \(error.localizedDescription)")
        }
    }
    
    
    // Function to handle retrieving passkey (get)
    func getCredentialAssertionRequest(_ challengeData:Data, rpId:String) {
        
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier:rpId)
        let assertionRequest = provider.createCredentialAssertionRequest(challenge: challengeData)
        
        let authController = ASAuthorizationController(authorizationRequests: [assertionRequest])
        authController.delegate = self
        authController.presentationContextProvider = self
        authController.performRequests()
    }
    
    // Helper method for Base64 URL decoding
    func base64UrlDecode(_ input: String) -> Data? {
        var base64 = input.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        switch base64.count % 4 {
        case 2: base64.append("==")
        case 3: base64.append("=")
        default: break
        }
        return Data(base64Encoded: base64)
    }
    
    // Helper method for Base64 URL encoding
    func base64UrlEncode(_ inputData: Data?) -> String {
        guard let input = inputData else {
            return ""
        }
        var base64 = input.base64EncodedString()
        
        // Replace characters to make it URL-safe
        base64 = base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        
        return base64
    }
    
    
    func handleHostedLoginRequest(_ message: HostedLoginMessage, callback:@escaping (_ data:[String: Any]?, _ error: Error?) -> Void) throws {
        
        guard let jsonData = message.payload.data(using: .utf8) else {
            throw FronteggError.authError(.invalidPasskeysRequest)
        }

        if(message.action == "getPasskey") {
            
            let request = try JSONDecoder().decode(GetPasskeysRequest.self, from: jsonData)
            
            guard let challengeData = base64UrlDecode(request.publicKey.challenge) else {
                throw FronteggError.authError(.invalidPasskeysRequest)
            }
            self.callbackAction = callback
            getCredentialAssertionRequest(challengeData, rpId: request.publicKey.rpId)
        }
        if (message.action == "createPasskey") {
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
            guard let dictionary = jsonObject as? [String: Any],
                  let publicKey = dictionary["publicKey"] as? [String: Any] else {
                throw FronteggError.authError(.invalidPasskeysRequest)
            }
        
            self.callbackAction = callback
            try createCredentialRegistrationRequest(with: publicKey)
        }
    }
    
    
    
    
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


