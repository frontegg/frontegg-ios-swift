//
//  WebauthnRegistration.swift
//
//
//  Created by David Antoon on 23/10/2024.
//

import Foundation
import AuthenticationServices



/// Struct representing the response of a WebAuthn registration,
/// containing the client data and attestation object.
struct WebauthnRegistrationResponse {
    let clientDataJSON: String        // JSON data that was sent to the authenticator
    let attestationObject: String?    // Attestation object returned by the authenticator (optional)

    /// Converts the WebauthnRegistrationResponse object into a dictionary format.
    /// - Returns: A dictionary containing all properties, excluding `nil` values.
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = ["clientDataJSON": clientDataJSON]
        
        // Optional values are only included in the dictionary if they are not nil.
        if let attestationObject = attestationObject {
            dict["attestationObject"] = attestationObject
        }
        
        return dict
    }
}

@available(iOS 15.0, *)
/// Struct representing a WebAuthn registration, which includes properties related to the public key credential registration.
struct WebauthnRegistration {
    let id: String                      // Base64-encoded credential ID
    let authenticatorAttachment: String = "platform" // The attachment method for the authenticator (e.g., platform)
    let response: WebauthnRegistrationResponse  // The response data associated with the WebAuthn registration
    let deviceType = "Platform"
    
    /// Initializes the WebauthnRegistration with data from a platform public key credential registration.
    /// - Parameter credential: An instance of `ASAuthorizationPlatformPublicKeyCredentialRegistration`
    /// which contains the WebAuthn registration data returned by the platform.
    init(credential: ASAuthorizationPlatformPublicKeyCredentialRegistration) {
        // Convert credential data into Base64-encoded strings
        self.id = credential.credentialID.toEncodedBase64()
        self.response = WebauthnRegistrationResponse(
            clientDataJSON: credential.rawClientDataJSON.toEncodedBase64(),
            attestationObject: credential.rawAttestationObject?.toEncodedBase64()
        )
    }
    
    /// Converts the WebauthnRegistration object into a dictionary format.
    /// - Returns: A dictionary containing all properties of the registration, ready for serialization.
    func toDictionary() -> [String: Any] {
        return [
            "id": id,
            "authenticatorAttachment": authenticatorAttachment,
            "response": response.toDictionary(),
            "deviceType": authenticatorAttachment == "platform" ? "Platform" : "CrossPlatform"
        ]
    }
}
