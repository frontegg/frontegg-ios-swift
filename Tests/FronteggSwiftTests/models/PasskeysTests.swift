//
//  PasskeysTests.swift
//  FronteggSwift
//
//  Created by Oleksii Minaiev on 05.02.2025.
//

import XCTest
@testable import FronteggSwift

class PasskeysTests: XCTestCase {
    let getPasskeysRequestModel = GetPasskeysRequest(
        publicKey:GetPasskeysRequest.PublicKeyCredential(
            timeout: 300,
            rpId: "example.com",
            userVerification: "required",
            challenge: "random-challenge-string"
        )
    )
    
    let createPasskeysRequestModel = CreatePasskeysRequest(publicKey: CreatePasskeysRequest.PublicKeyCredential(
        rp: CreatePasskeysRequest.PublicKeyCredential.Rp (
            name: "Example RP",
            id: "example.com"
        ),
        user: CreatePasskeysRequest.PublicKeyCredential.User(
            id: [
                "userId": "12345"
            ],
            name: "John Doe",
            displayName: "John"
        ),
        challenge: "random-challenge-string",
        pubKeyCredParams: [
            CreatePasskeysRequest.PublicKeyCredential.PubKeyCredParam(
                type: "public-key",
                alg: -7
            )
        ],
        timeout: 300,
        attestation: "direct",
        authenticatorSelection: CreatePasskeysRequest.PublicKeyCredential.AuthenticatorSelection(
            userVerification: "required"
        ),
        excludeCredentials: ["cred-001", "cred-002"]
        
    ))
    
    
    let getPasskeysRequestJson = """
{
  "publicKey": {
    "timeout": 300,
    "rpId": "example.com",
    "userVerification": "required",
    "challenge": "random-challenge-string"
  }
}
"""
    
    let createPasskeysRequestJson = """
{
  "publicKey": {
    "rp": {
      "name": "Example RP",
      "id": "example.com"
    },
    "user": {
      "id": {
        "userId": "12345"
      },
      "name": "John Doe",
      "displayName": "John"
    },
    "challenge": "random-challenge-string",
    "pubKeyCredParams": [
      {
        "type": "public-key",
        "alg": -7
      }
    ],
    "timeout": 300,
    "attestation": "direct",
    "authenticatorSelection": {
      "userVerification": "required"
    },
    "excludeCredentials": ["cred-001", "cred-002"]
  }
}
"""
    
    
    func test_shouldDecodeGetPasskeysRequestJsonToModel () {
        let data = getPasskeysRequestJson.data(using: .utf8)!
        
        guard let model = try? JSONDecoder().decode(GetPasskeysRequest.self, from: data) else {
            XCTAssertTrue(false, "Model should be decoded")
            return
        }
        XCTAssertEqual(model, self.getPasskeysRequestModel)
    }
    
    func test_shouldEncodeGetPasskeysRequestModelToJson () {
        // Convert json string to dictionary
        guard let jsonData = getPasskeysRequestJson.data(using: .utf8),
              let expectedMap = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
            XCTFail("Failed to convert JSON string to dictionary")
            return
        }
        
        // Encode model to JSON
        guard let encodedData = try? JSONEncoder().encode(self.getPasskeysRequestModel),
              let encodedMap = try? JSONSerialization.jsonObject(with: encodedData, options: []) as? [String: Any] else {
            XCTFail("Model should be encoded successfully")
            return
        }
        
        // Compare the dictionaries (maps)
        XCTAssertTrue(NSDictionary(dictionary:expectedMap).isEqual(to:encodedMap), "Encoded model does not match the expected JSON")
    }
    
    
    
    
    
    func test_shouldDecodeCreatePasskeysRequestJsonToModel () {
        let data = createPasskeysRequestJson.data(using: .utf8)!
        
        guard let model = try? JSONDecoder().decode(CreatePasskeysRequest.self, from: data) else {
            XCTAssertTrue(false, "Model should be decoded")
            return
        }
        XCTAssertEqual(model, createPasskeysRequestModel)
    }
    
    func test_shouldEncodeCreatePasskeysRequestModelToJson () {
        // Convert json string to dictionary
        guard let jsonData = createPasskeysRequestJson.data(using: .utf8),
              let expectedMap = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
            XCTFail("Failed to convert JSON string to dictionary")
            return
        }
        
        // Encode model to JSON
        guard let encodedData = try? JSONEncoder().encode(self.createPasskeysRequestModel),
              let encodedMap = try? JSONSerialization.jsonObject(with: encodedData, options: []) as? [String: Any] else {
            XCTFail("Model should be encoded successfully")
            return
        }
        
        // Compare the dictionaries (maps)
        XCTAssertTrue(NSDictionary(dictionary:expectedMap).isEqual(to:encodedMap), "Encoded model does not match the expected JSON")
    }
}
