//
//  FronteggApi.swift
//
//  Created by David Frontegg on 16/11/2022.
//

import Foundation


enum ApiError: Error {
    case invalidUrl(String)
}


class RedirectHandler: NSObject, URLSessionTaskDelegate {
    // This method allows you to control redirect behavior
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // By passing nil to the completionHandler, we tell the session to not follow the redirect
        completionHandler(nil)
    }
}


public class Api {
    private let logger = getLogger("Api")
    private let baseUrl: String
    private let clientId: String
    private let applicationId: String?
    private var cookieName: String
    private let credentialManager: CredentialManager
    
    init(baseUrl: String, clientId: String, applicationId: String?) {
        self.baseUrl = baseUrl
        self.clientId = clientId
        self.applicationId = applicationId
        self.credentialManager = CredentialManager(serviceKey: "frontegg")
        
        self.cookieName = "fe_refresh_\(clientId)"
        if let range = self.cookieName.range(of: "-") {
            self.cookieName.removeSubrange(range)
        }
    }
    
    internal func putRequest(path:String, body: [String: Any?]) async throws -> (Data, URLResponse) {
        let urlStr = "\(self.baseUrl)/\(path)"
        guard let url = URL(string: urlStr) else {
            throw ApiError.invalidUrl("invalid url: \(urlStr)")
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(self.baseUrl, forHTTPHeaderField: "Origin")
        
        if (self.applicationId != nil) {
            request.setValue(self.applicationId, forHTTPHeaderField: "frontegg-requested-application-id")
        }
        
        if let accessToken = try? credentialManager.get(key: KeychainKeys.accessToken.rawValue) {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "authorization")
        }
        
        request.httpMethod = "PUT"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        return try await URLSession.shared.data(for: request)
    }
    
    internal func postRequest(path:String, body: [String: Any?], additionalHeaders: [String: String] = [:], followRedirect:Bool = true) async throws -> (Data, URLResponse) {
        let urlStr = if(path.starts(with: self.baseUrl)) {
            path
        }else{
            "\(self.baseUrl)\(path.starts(with: "/") ? path : "/\(path)")"
        }
        
        guard let url = URL(string: urlStr) else {
            throw ApiError.invalidUrl("invalid url: \(urlStr)")
        }
        
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(self.baseUrl, forHTTPHeaderField: "Origin")
        
        if (self.applicationId != nil) {
            request.setValue(self.applicationId, forHTTPHeaderField: "frontegg-requested-application-id")
        }
        
        additionalHeaders.forEach({ (key: String, value: String) in
            request.setValue(value, forHTTPHeaderField: key)
        })
        
        if let accessToken = try? credentialManager.get(key: KeychainKeys.accessToken.rawValue) {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        if(!followRedirect){
            // Create a custom URLSession with the redirect handler
            let redirectHandler = RedirectHandler()
            let sessionConfig = URLSessionConfiguration.default
            let session = URLSession(configuration: sessionConfig, delegate: redirectHandler, delegateQueue: nil)
            return try await session.data(for: request)
            
        }
        
        return try await URLSession.shared.data(for: request)
    }
    
    internal func silentAuthorize(refreshToken:String, deviceToken:String) async throws -> (Data, URLResponse) {
        let urlStr = "\(self.baseUrl)/oauth/authorize/silent"
        guard let url = URL(string: urlStr) else {
            throw ApiError.invalidUrl("invalid url: \(urlStr)")
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(self.baseUrl, forHTTPHeaderField: "Origin")
        
        if (self.applicationId != nil) {
            request.setValue(self.applicationId, forHTTPHeaderField: "frontegg-requested-application-id")
        }
        
        request.setValue("\(refreshToken);\(deviceToken)", forHTTPHeaderField: "Cookie")
        
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: [:])
        
        return try await URLSession.shared.data(for: request)
    }
    
    internal func getRequest(path:String, accessToken:String?, refreshToken: String? = nil, additionalHeaders: [String: String] = [:], followRedirect:Bool = true) async throws -> (Data, URLResponse) {
        
        
        
        let urlStr = if(path.starts(with: self.baseUrl)) {
            path
        }else{
            "\(self.baseUrl)\(path.starts(with: "/") ? path : "/\(path)")"
        }
        
        guard let url = URL(string: urlStr) else {
            throw ApiError.invalidUrl("invalid url: \(urlStr)")
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(self.baseUrl, forHTTPHeaderField: "Origin")
        if(accessToken != nil){
            request.setValue("Bearer \(accessToken!)", forHTTPHeaderField: "Authorization")
        }
        if(refreshToken != nil){
            let cookieHeaderValue = "\(self.cookieName)=\(refreshToken!)"
            request.setValue(cookieHeaderValue, forHTTPHeaderField: "Cookie")
        }
        if (self.applicationId != nil) {
            request.setValue(self.applicationId, forHTTPHeaderField: "frontegg-requested-application-id")
        }
        
        additionalHeaders.forEach({ (key: String, value: String) in
            request.setValue(value, forHTTPHeaderField: key)
        })
        
        request.httpMethod = "GET"
        
        
        if(!followRedirect){
            // Create a custom URLSession with the redirect handler
            let redirectHandler = RedirectHandler()
            let sessionConfig = URLSessionConfiguration.default
            let session = URLSession(configuration: sessionConfig, delegate: redirectHandler, delegateQueue: nil)
            return try await session.data(for: request)
            
        }
        
        return try await URLSession.shared.data(for: request)
    }
    
    internal func refreshToken(refreshToken: String) async throws -> AuthResponse {
        let (data, response) = try await postRequest(path: "oauth/token", body: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])
        
        if let res = response as? HTTPURLResponse, res.statusCode == 401 {
            self.logger.error("failed to refresh token, error: \(String(data: data, encoding: .utf8) ?? "unknown error")")
            throw FronteggError.authError(.failedToRefreshToken)
        }
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }
    
    
    internal func refreshTokenForMfa(refreshTokenCookie: String) async -> [String:Any]? {
        do {
            let (refeshTokenForMfaData, _) = try await postRequest(path: "frontegg/identity/resources/auth/v1/user/token/refresh",  body: [
                "tenantId": nil
            ], additionalHeaders: [
                "Cookie": refreshTokenCookie
            ])
            
            if let jsonResponse = try? JSONSerialization.jsonObject(with: refeshTokenForMfaData, options: []) as? [String: Any] {
                return jsonResponse
            }
            return nil
        } catch {
            print(error)
            return nil
        }
    }
    
    internal func exchangeToken(code: String,
                                redirectUrl: String,
                                codeVerifier: String) async -> (AuthResponse?, FronteggError?) {
        do {
            let (data, _) = try await postRequest(path: "oauth/token", body: [
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": redirectUrl,
                "code_verifier": codeVerifier,
            ])
            
            return (try JSONDecoder().decode(AuthResponse.self, from: data), nil)
        }catch {
            return (nil, FronteggError.authError(.couldNotExchangeToken(error.localizedDescription)))
        }
    }
    
    internal func me(accessToken: String) async throws -> User? {
        let (meData, _) = try await getRequest(path: "identity/resources/users/v2/me", accessToken: accessToken)
        
        var meObj = try JSONSerialization.jsonObject(with: meData, options: [])  as! [String: Any]
        
        let (tenantsData, _) = try await getRequest(path: "identity/resources/users/v3/me/tenants", accessToken: accessToken)
        
        let tenantsObj = try JSONSerialization.jsonObject(with: tenantsData, options: [])  as! [String: Any]
        
        meObj["tenants"] = tenantsObj["tenants"]
        meObj["activeTenant"] = tenantsObj["activeTenant"]
        
        let mergedData = try JSONSerialization.data(withJSONObject: meObj)
        
        
        return try JSONDecoder().decode(User.self, from: mergedData)
    }
    
    
    public func switchTenant(tenantId: String) async throws -> Void {
        _ = try await putRequest(path: "identity/resources/users/v1/tenant", body: ["tenantId":tenantId])
    }
    
    internal func logout(accessToken: String?, refreshToken: String?) async {
        
        do {
            let (_, response) = try await postRequest(path: "identity/resources/auth/v1/logout", body: ["refreshToken":refreshToken])
            
            if let res = response as? HTTPURLResponse, res.statusCode != 401 {
                self.logger.info("logged out successfully")
            }else {
                self.logger.info("Already logged out")
            }
        }catch {
            self.logger.info("Uknonwn error when try to logout: \(error)")
        }
    }
    
    internal func getCookiesFromHeaders(response: HTTPURLResponse) -> (String?, String?)? {
        let setCookieHeader = response.value(forHTTPHeaderField: "Set-Cookie") ?? ""
        
        return  (
            getCookieValueFromHeaders(setCookieHeader: setCookieHeader, cookieName: "fe_refresh"),
            getCookieValueFromHeaders(setCookieHeader: setCookieHeader, cookieName: "fe_device")
        )
    }
    
    internal func getCookieValueFromHeaders(setCookieHeader:String, cookieName:String) -> String? {
        
        // Regular expression to find the fe_refresh cookie value
        let pattern = "\(cookieName)_\\S+=([^;]+)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: setCookieHeader, options: [], range: NSRange(setCookieHeader.startIndex..., in: setCookieHeader)) {
            
            if let range = Range(match.range(at: 0), in: setCookieHeader) {
                let feRefreshValue = String(setCookieHeader[range])
                self.logger.info("\(cookieName) cookie found")
                return feRefreshValue
            } else {
                self.logger.info("No \(cookieName) cookie")
            }
        } else {
            self.logger.error("Invalid regex or no match found")
        }
        return nil
    }
    
    
    internal func webauthnDevices() {
        
    }
    
    internal func preloginWebauthn() async throws -> WebauthnPreloginResponse {
        self.logger.info("Start webauthn prelogin")
        let (data, response) = try await FronteggAuth.shared.api.postRequest(path: "frontegg/identity/resources/auth/v1/webauthn/prelogin", body: [:])
        
        guard let preloginHTTPResponse = response as? HTTPURLResponse, preloginHTTPResponse.statusCode == 200 else {
            throw FronteggError.authError(.failedToAuthenticate)
        }
        
        return try JSONDecoder().decode(WebauthnPreloginResponse.self, from: data)
        
    }
    
    @available(iOS 15.0, *)
    internal func postloginWebauthn(assertion: WebauthnAssertion) async throws -> AuthResponse {
        
        // Perform the post request
        let (postloginResponseData, postloginResponse) = try await FronteggAuth.shared.api.postRequest(
            path: "frontegg/identity/resources/auth/v1/webauthn/postlogin",
            body: assertion.toDictionary()
        )
        
        // Check if the response is a valid HTTP response
        guard let postloginHTTPResponse = postloginResponse as? HTTPURLResponse else {
            throw FronteggError.authError(.invalidPasskeysRequest)
        }
        
        // Decode the response data to check if MFA is required
        if let jsonResponse = try? JSONSerialization.jsonObject(with: postloginResponseData, options: []) as? [String: Any],
           let mfaRequired = jsonResponse["mfaRequired"] as? Bool, mfaRequired == true {
            // Throw an exception if MFA is required
            throw FronteggError.authError(.mfaRequired(jsonResponse))
        }
        
        // Extract cookies for further authorization
        guard let cookies = FronteggAuth.shared.api.getCookiesFromHeaders(response: postloginHTTPResponse),
              let refreshToken = cookies.0, let deviceToken = cookies.1 else {
            if let httpError = String(data: postloginResponseData, encoding: .utf8) {
                throw FronteggError.authError(.failedToAuthenticateWithPasskeys(httpError))
            } else {
                throw FronteggError.authError(.failedToAuthenticateWithPasskeys("No cookies returns from postLogin request"))
            }
        }
        
        // Silent authorize with the extracted tokens
        let (data, _) = try await FronteggAuth.shared.api.silentAuthorize(refreshToken: refreshToken, deviceToken: deviceToken)
        
        // Decode and return the AuthResponse
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }
    
    
    
    public func getSocialLoginConfig() async throws -> SocialLoginConfig {
        let (jsonData, _) = try await FronteggAuth.shared.api.getRequest(path: "/frontegg/identity/resources/sso/v2", accessToken: nil)
        let options = try JSONDecoder().decode([SocialLoginOption].self, from: jsonData)
        
        return SocialLoginConfig(options: options)
    }
    
    
    
    @available(iOS 15.0, *)
    internal func postloginAppleNative(_ code: String) async throws -> AuthResponse {
        
        var urlComponents = URLComponents(string: "\(self.baseUrl)/frontegg/identity/resources/auth/v1/user/sso/apple/postlogin")!
        
        urlComponents.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "clientId", value: Bundle.main.bundleIdentifier),
            URLQueryItem(name: "redirectUri", value: "\(self.baseUrl)/oauth/account/social/success"),
            URLQueryItem(name: "state", value: "{\"provider\":\"apple\",\"appId\":\"\",\"action\":\"login\"}")
        ]
        // Perform the post request
        let (postloginResponseData, postloginResponse) = try await FronteggAuth.shared.api.postRequest(
            path: urlComponents.url!.absoluteString,
            body: [:]
        )
        
        // Check if the response is a valid HTTP response
        guard let postloginHTTPResponse = postloginResponse as? HTTPURLResponse, postloginHTTPResponse.statusCode == 200 else {
            throw FronteggError.authError(.couldNotExchangeToken(String(data: postloginResponseData, encoding: .utf8) ?? "Unknown error occured"))
        }
        
        // Decode the response data to check if MFA is required
        if let jsonResponse = try? JSONSerialization.jsonObject(with: postloginResponseData, options: []) as? [String: Any],
           let mfaRequired = jsonResponse["mfaRequired"] as? Bool, mfaRequired == true {
            
            if let cookies = FronteggAuth.shared.api.getCookiesFromHeaders(response: postloginHTTPResponse),
                  let refreshToken = cookies.0 {
                throw FronteggError.authError(.mfaRequired(jsonResponse, refreshToken: refreshToken))
            }
            // Throw an exception if MFA is required
            throw FronteggError.authError(.mfaRequired(jsonResponse))
        }
        
        // Extract cookies for further authorization
        guard let cookies = FronteggAuth.shared.api.getCookiesFromHeaders(response: postloginHTTPResponse),
              let refreshToken = cookies.0, let deviceToken = cookies.1 else {
            throw FronteggError.authError(.invalidPasskeysRequest)
        }
        
        // Silent authorize with the extracted tokens
        let (data, _) = try await FronteggAuth.shared.api.silentAuthorize(refreshToken: refreshToken, deviceToken: deviceToken)
        
        // Decode and return the AuthResponse
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }
}
