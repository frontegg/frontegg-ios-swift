//
//  File.swift
//  
//
//  Created by David Antoon on 15/10/2024.
//

import Foundation
import AuthenticationServices

// Coordinator to handle ASAuthorizationController delegation
@available(iOS 15.0, *)
class PasskeysAuthenticator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {

    public static let shared = PasskeysAuthenticator()
    let baseUrl:String = "https://autheu.davidantoon.me"
    
    func startWebAuthn() {
        
        // 1. Create New Device Session (request options)
        guard let url = URL(string: "\(baseUrl)/frontegg/identity/resources/users/webauthn/v1/devices") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(FronteggAuth.shared.accessToken ?? "")", forHTTPHeaderField: "authorization")
        request.setValue("https://autheu.davidantoon.me", forHTTPHeaderField: "origin")
        
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
                self.createCredentialRegistrationRequest(with: options)
            }
        }
        
        task.resume()
    }

    // This function handles the WebAuthn creation request
    func createCredentialRegistrationRequest(with options: [String: Any]) {
        guard let challenge = options["challenge"] as? String,
              let userId = options["user"] as? [String: Any],
              let userIdData = base64UrlDecode(userId["id"] as! String),
              let challengeData = base64UrlDecode(challenge) else {
            return
        }
        
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: "davidantoon.me")
        let registrationRequest = provider.createCredentialRegistrationRequest(
            challenge: challengeData,
            name: "Passkey \(FronteggAuth.shared.user?.email ?? "")",
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

            // Send the publicKey and result to verify on the backend
            let publicKey = [
                "id": credentialID.base64EncodedString(),
                "response": [
                    "clientDataJSON": clientDataJSON.base64EncodedString(),
                    "attestationObject": attestationObject?.base64EncodedString()
                ],
                "authenticatorAttachment": "platform"
            ] as [String : Any]
            
            verifyNewDeviceSession(publicKey: publicKey)
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
        guard let url = URL(string: "\(baseUrl)/identity/resources/users/webauthn/v1/devices/verify") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(FronteggAuth.shared.accessToken ?? "")", forHTTPHeaderField: "authorization")
        request.setValue("https://autheu.davidantoon.me", forHTTPHeaderField: "origin")
        
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
}
