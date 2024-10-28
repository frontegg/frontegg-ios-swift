//
//  WebauthnPreloginResponse.swift
//
//
//  Created by David Antoon on 23/10/2024.
//

import Foundation

/// A struct representing the response from the WebAuthn pre-login process.
/// It decodes the values from the `options` section of the JSON response.
public struct WebauthnPreloginResponse: Decodable {
    
    // MARK: - Properties
    
    /// The timeout value for the WebAuthn process, in milliseconds.
    let timeout: Int
    
    /// The relying party (RP) ID, representing the entity responsible for the authentication.
    let rpId: String
    
    /// The user verification requirement for the WebAuthn process.
    let userVerification: String
    
    /// The challenge to be used in the WebAuthn process, decoded as Data from Base64URL.
    let challenge: Data
    
    // MARK: - Initializer
    
    /// Custom initializer to handle decoding from the provided JSON decoder.
    /// This initializer expects the data to be nested under an `options` key.
    /// - Parameter decoder: The decoder used to decode the JSON data.
    /// - Throws: An error if the decoding process fails or the challenge is not valid Base64URL.
    public init(from decoder: Decoder) throws {
        // Access the top-level container
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode the 'options' dictionary
        let optionsContainer = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .options)
        
        // Decode each field inside 'options'
        timeout = try optionsContainer.decode(Int.self, forKey: .timeout)
        rpId = try optionsContainer.decode(String.self, forKey: .rpId)
        userVerification = try optionsContainer.decode(String.self, forKey: .userVerification)
        
        // Decode the challenge as a Base64URL string and convert it to Data
        let challengeString = try optionsContainer.decode(String.self, forKey: .challenge)
        guard let decodedChallenge = challengeString.toDecodedData() else {
            throw DecodingError.dataCorruptedError(forKey: .challenge,
                                                   in: optionsContainer,
                                                   debugDescription: "Challenge is not valid Base64URL encoded string")
        }
        challenge = decodedChallenge
    }
    
    // MARK: - Coding Keys
    
    /// Defines the keys to match the JSON keys with the struct's properties.
    enum CodingKeys: String, CodingKey {
        case options  // The container key for the options object
        case timeout  // The timeout value inside 'options'
        case rpId     // The rpId value inside 'options'
        case userVerification // The userVerification value inside 'options'
        case challenge // The challenge value inside 'options'
    }
}
