//
//  mocker.swift
//  demo-test
//
//  Created by David Frontegg on 19/04/2023.
//

import Foundation


enum MockMethod: String {
    case mockEmbeddedRefreshToken
    case mockSSOPrelogin
    case mockHostedLoginAuthorize
    case mockHostedLoginRefreshToken
    case mockLogout
    case mockGetMe
    case mockGetMeTenants
    case mockAuthUser
    case mockSessionsConfigurations
    case mockOauthPostlogin
    
}



enum MockDataMethod: String {
    case generateUser
}

struct Mocker {
    
    static var baseUrl:String!
    static var clientId:String!

    
    static func fronteggConfig(bundle:Bundle) throws -> (clientId: String, baseUrl: String) {
        
        guard let url = bundle.url(forResource: "FronteggTest", withExtension: "plist") else {
            print("Failed to locate plist file.")
            exit(1)
        }
        guard let plistData = try? Data(contentsOf: url) else {
            print("Failed to read plist file.")
            exit(1)
        }
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            print("Failed to deserialize plist data.")
            exit(1)
        }
        
        guard let clientId = plist["clientId"] as? String, let baseUrl = plist["baseUrl"] as? String else {
            let errorMessage = "Frontegg.plist file at is missing 'clientId' and/or 'baseUrl' entries!"
            print(errorMessage)
            exit(1)
        }
        
        Mocker.baseUrl = baseUrl
        Mocker.clientId = clientId
        return (clientId: clientId, baseUrl: baseUrl)
    }
    
    
    
    static func mock(name: MockMethod, body: [String: Any?]) async -> String {
        
        let urlStr = "http://localhost:4001/mock/\(name.rawValue)"
        let url = URL(string: urlStr)
        var request = URLRequest(url: url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("http://localhost:4001", forHTTPHeaderField: "Origin")
        request.httpMethod = "POST"
        
        let json = try? JSONSerialization.data(withJSONObject: body)
        request.httpBody = json
        
        let (data, _) :(Data, URLResponse) = try! await URLSession.shared.data(for: request)
        
        let x = String(data: data, encoding: .utf8)!
        print("id: \(x)")
        
        return x;
    }
    
    static func mockData(name: MockDataMethod, body: [Any]) async -> Any {
        
        let jsonData = try? JSONSerialization.data(withJSONObject: body)
        let jsonStr = String(data:jsonData!, encoding: .utf8)
        
        let query = jsonStr!.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        
        let urlStr = "\(Mocker.baseUrl!)/faker/\(name.rawValue)?options=\(query!)";
        
        print(urlStr)
        let url = URL(string: urlStr)!
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("http://localhost:4001", forHTTPHeaderField: "Origin")
        request.httpMethod = "GET"

        
        
        let (data, _) :(Data, URLResponse) = try! await URLSession.shared.data(for: request)
        
        
        return (try! JSONSerialization.jsonObject(with: data, options: []) as! [String: Any])["data"]
    }
    
    
    
    
    
    static  func mockClearMocks() async {
        let urlStr = "\(Mocker.baseUrl!)/clear-mock"
        let url = URL(string: urlStr)
        var request = URLRequest(url: url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("http://localhost:4001", forHTTPHeaderField: "Origin")
        request.httpMethod = "POST"
        _ = try! await URLSession.shared.data(for: request)
    }
    static  func mockSuccessPasswordLogin() async {
        
        let mockedUser = await Mocker.mockData(name: .generateUser, body: [Mocker.clientId!, ["email":"test@frontegg.com"]])
        as! [String: Any]
        
        var authUserOptions: [String: Any] = [
            "success":true,
            "user": mockedUser
        ]
        await Mocker.mock(name: .mockAuthUser, body: ["options": authUserOptions])
        await Mocker.mock(name: .mockHostedLoginRefreshToken, body: [
            "partialRequestBody": [:],
            "options":[
            "success":true,
            "refreshTokenResponse": mockedUser["refreshTokenResponse"],
            "refreshTokenCookie": mockedUser["refreshTokenCookie"],
        ]])
        await Mocker.mock(name: .mockEmbeddedRefreshToken, body: [
            "options":[
                "success":true,
                "refreshTokenResponse": mockedUser["refreshTokenResponse"],
                "refreshTokenCookie": mockedUser["refreshTokenCookie"],
            ]])
        await Mocker.mock(name: .mockGetMeTenants, body: ["options":mockedUser])
        await Mocker.mock(name: .mockGetMe, body: ["options":mockedUser])
        await Mocker.mock(name: .mockSessionsConfigurations, body: [:])
        
        
    }
    
}
