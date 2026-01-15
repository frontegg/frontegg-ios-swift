//
//  FronteggApi.swift
//
//  Created by David Frontegg on 16/11/2022.
//

import Foundation
import Sentry


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
    internal static let DEFAULT_TIMEOUT: Int = 10
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
        
        var clientIdWithoutFirstDash = clientId
        if let firstDashIndex = clientId.firstIndex(of: "-") {
            clientIdWithoutFirstDash.remove(at: firstDashIndex)
        }
        self.cookieName = "fe_refresh_\(clientIdWithoutFirstDash)"
    }

    private func addHttpBreadcrumb(
        method: String,
        url: URL?,
        statusCode: Int?,
        traceId: String?,
        durationMs: Int?,
        requestBodySize: Int?,
        responseBodySize: Int?,
        followRedirect: Bool,
        error: Error? = nil
    ) {
        guard let url else { return }

        let host = url.host ?? "unknown"
        let path = url.path.isEmpty ? "/" : url.path

        var data: [String: Any] = [
            "method": method,
            "host": host,
            "path": path,
            "followRedirect": followRedirect,
            "request_body_size": requestBodySize ?? 0,
            "response_body_size": responseBodySize ?? 0
        ]

        if let statusCode {
            data["status_code"] = statusCode
            data["status_reason"] = HTTPURLResponse.localizedString(forStatusCode: statusCode)
        }
        if let traceId, !traceId.isEmpty {
            data["frontegg_trace_id"] = traceId
        }
        if let durationMs {
            data["duration_ms"] = durationMs
        }
        if let error {
            let nsError = error as NSError
            data["error_domain"] = nsError.domain
            data["error_code"] = nsError.code
            // Prefer a non-localized description (type + domain/code/userInfo where available).
            data["error_description"] = String(reflecting: error)
        }

        // Breadcrumb message intentionally avoids full URL (queries may contain PII).
        let message = "HTTP \(method) \(path)"
        let level: SentryLevel = (statusCode != nil && !(200...299).contains(statusCode!)) || error != nil ? .warning : .info
        SentryHelper.addBreadcrumb(message, category: "http", level: level, data: data)
    }
    
    internal func putRequest(
        path: String,
        body: [String: Any?],
        timeout: Int = Api.DEFAULT_TIMEOUT
    ) async throws -> (Data, URLResponse) {
        let urlStr = "\(self.baseUrl)/\(path)"
        guard let url = URL(string: urlStr) else {
            throw ApiError.invalidUrl("invalid url: \(urlStr)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(self.baseUrl, forHTTPHeaderField: "Origin")
        if let applicationId = self.applicationId {
            request.setValue(applicationId, forHTTPHeaderField: "frontegg-requested-application-id")
        }
        if let accessToken = try? credentialManager.get(key: KeychainKeys.accessToken.rawValue) {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let requestBodySize = request.httpBody?.count
        
        // per-task timeout
        request.timeoutInterval = TimeInterval(timeout)
        
        // session-level timeouts
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = TimeInterval(timeout)
        config.timeoutIntervalForResource = TimeInterval(timeout)
        config.waitsForConnectivity = false
        
        let session = URLSession(configuration: config)
        let start = Date()
        do {
            let (data, response) = try await session.data(for: request)
            let durationMs = Int(Date().timeIntervalSince(start) * 1000.0)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            TraceIdLogger.shared.extractAndLogTraceId(from: response)
            addHttpBreadcrumb(
                method: "PUT",
                url: request.url,
                statusCode: statusCode,
                traceId: (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "frontegg-trace-id"),
                durationMs: durationMs,
                requestBodySize: requestBodySize,
                responseBodySize: data.count,
                followRedirect: true
            )
            return (data, response)
        } catch {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000.0)
            addHttpBreadcrumb(
                method: "PUT",
                url: request.url,
                statusCode: nil,
                traceId: nil,
                durationMs: durationMs,
                requestBodySize: requestBodySize,
                responseBodySize: nil,
                followRedirect: true,
                error: error
            )
            SentryHelper.logError(error, context: [
                "http": [
                    "method": "PUT",
                    "path": path
                ]
            ])
            throw error
        }
    }
    
    internal func postRequest(
        path: String,
        body: [String: Any?],
        additionalHeaders: [String: String] = [:],
        followRedirect: Bool = true,
        timeout: Int = Api.DEFAULT_TIMEOUT
    ) async throws -> (Data, URLResponse) {
        // Build URL
        let urlStr = path.starts(with: self.baseUrl)
        ? path
        : "\(self.baseUrl)\(path.starts(with: "/") ? path : "/\(path)")"
        
        guard let url = URL(string: urlStr) else {
            throw ApiError.invalidUrl("invalid url: \(urlStr)")
        }
        
        // Prepare request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(self.baseUrl, forHTTPHeaderField: "Origin")
        
        if let applicationId = self.applicationId {
            request.setValue(applicationId, forHTTPHeaderField: "frontegg-requested-application-id")
        }
        
        additionalHeaders.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Only add Authorization header from keychain if it's not already set in additionalHeaders
        // This allows callers to explicitly provide an access token (e.g., for tenant-specific refresh)
        if request.value(forHTTPHeaderField: "Authorization") == nil && !path.contains("oauth/token") {
            if let accessToken = try? credentialManager.get(key: KeychainKeys.accessToken.rawValue) {
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            }
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let requestBodySize = request.httpBody?.count
        
        // Apply per-task timeout (covers the whole transfer for this request)
        request.timeoutInterval = TimeInterval(timeout)
        
        // Session-level timeouts (cover request + resource)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = TimeInterval(timeout)          // idle time between bytes / request phase
        config.timeoutIntervalForResource = TimeInterval(timeout)         // total resource load time
        config.waitsForConnectivity = false                               // fail fast if offline (optional)
        
        // Choose session (with or without redirect following)
        let session: URLSession
        if followRedirect {
            session = URLSession(configuration: config)
        } else {
            let redirectHandler = RedirectHandler()
            session = URLSession(configuration: config, delegate: redirectHandler, delegateQueue: nil)
        }
        
        let start = Date()
        do {
            let (data, response) = try await session.data(for: request)
            let durationMs = Int(Date().timeIntervalSince(start) * 1000.0)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            TraceIdLogger.shared.extractAndLogTraceId(from: response)
            addHttpBreadcrumb(
                method: "POST",
                url: request.url,
                statusCode: statusCode,
                traceId: (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "frontegg-trace-id"),
                durationMs: durationMs,
                requestBodySize: requestBodySize,
                responseBodySize: data.count,
                followRedirect: followRedirect
            )
            return (data, response)
        } catch {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000.0)
            addHttpBreadcrumb(
                method: "POST",
                url: request.url,
                statusCode: nil,
                traceId: nil,
                durationMs: durationMs,
                requestBodySize: requestBodySize,
                responseBodySize: nil,
                followRedirect: followRedirect,
                error: error
            )
            SentryHelper.logError(error, context: [
                "http": [
                    "method": "POST",
                    "path": path,
                    "followRedirect": followRedirect
                ]
            ])
            throw error
        }
    }
    
    internal func getRequest(
        path: String,
        accessToken: String?,
        refreshToken: String? = nil,
        additionalHeaders: [String: String] = [:],
        followRedirect: Bool = true,
        timeout: Int = Api.DEFAULT_TIMEOUT
    ) async throws -> (Data, URLResponse) {
        let urlStr = path.starts(with: self.baseUrl)
            ? path
            : "\(self.baseUrl)\(path.starts(with: "/") ? path : "/\(path)")"

        guard let url = URL(string: urlStr) else {
            throw ApiError.invalidUrl("invalid url: \(urlStr)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(self.baseUrl, forHTTPHeaderField: "Origin")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        if let refreshToken {
            request.setValue("\(self.cookieName)=\(refreshToken)", forHTTPHeaderField: "Cookie")
        }
        if let applicationId = self.applicationId {
            request.setValue(applicationId, forHTTPHeaderField: "frontegg-requested-application-id")
        }
        additionalHeaders.forEach { k, v in request.setValue(v, forHTTPHeaderField: k) }

        // per-task timeout
        request.timeoutInterval = TimeInterval(timeout)

        // session-level timeouts
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = TimeInterval(timeout)
        config.timeoutIntervalForResource = TimeInterval(timeout)
        config.waitsForConnectivity = false

        let session: URLSession
        if followRedirect {
            session = URLSession(configuration: config)
        } else {
            let redirectHandler = RedirectHandler()
            session = URLSession(configuration: config, delegate: redirectHandler, delegateQueue: nil)
        }

        let start = Date()
        do {
            let (data, response) = try await session.data(for: request)
            let durationMs = Int(Date().timeIntervalSince(start) * 1000.0)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            TraceIdLogger.shared.extractAndLogTraceId(from: response)
            addHttpBreadcrumb(
                method: "GET",
                url: request.url,
                statusCode: statusCode,
                traceId: (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "frontegg-trace-id"),
                durationMs: durationMs,
                requestBodySize: nil,
                responseBodySize: data.count,
                followRedirect: followRedirect
            )
            return (data, response)
        } catch {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000.0)
            addHttpBreadcrumb(
                method: "GET",
                url: request.url,
                statusCode: nil,
                traceId: nil,
                durationMs: durationMs,
                requestBodySize: nil,
                responseBodySize: nil,
                followRedirect: followRedirect,
                error: error
            )
            SentryHelper.logError(error, context: [
                "http": [
                    "method": "GET",
                    "path": path,
                    "followRedirect": followRedirect
                ]
            ])
            throw error
        }
    }

    
    public func silentAuthorize(
        refreshToken: String,
        timeout: Int = 10
    ) async throws -> (Data, URLResponse) {
        // Use POST /frontegg/oauth/authorize/silent with cookie fe_refresh_client-id=refresh-token
        let urlStr = "/frontegg/oauth/authorize/silent"
        let fullUrl = urlStr.starts(with: self.baseUrl)
            ? urlStr
            : "\(self.baseUrl)\(urlStr.starts(with: "/") ? urlStr : "/\(urlStr)")"
        
        guard let url = URL(string: fullUrl) else {
            throw ApiError.invalidUrl("invalid url: \(fullUrl)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(self.baseUrl, forHTTPHeaderField: "Origin")
        request.setValue("\(self.cookieName)=\(refreshToken)", forHTTPHeaderField: "Cookie")
        
        if let applicationId = self.applicationId {
            request.setValue(applicationId, forHTTPHeaderField: "frontegg-requested-application-id")
        }
        
        // Empty body for POST request
        request.httpBody = try JSONSerialization.data(withJSONObject: [:])
        let requestBodySize = request.httpBody?.count
        
        // per-task timeout
        request.timeoutInterval = TimeInterval(timeout)
        
        // session-level timeouts
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = TimeInterval(timeout)
        config.timeoutIntervalForResource = TimeInterval(timeout)
        config.waitsForConnectivity = false
        
        let session = URLSession(configuration: config)
        let start = Date()
        do {
            let (data, response) = try await session.data(for: request)
            let durationMs = Int(Date().timeIntervalSince(start) * 1000.0)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            TraceIdLogger.shared.extractAndLogTraceId(from: response)
            addHttpBreadcrumb(
                method: "POST",
                url: request.url,
                statusCode: statusCode,
                traceId: (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "frontegg-trace-id"),
                durationMs: durationMs,
                requestBodySize: requestBodySize,
                responseBodySize: data.count,
                followRedirect: true
            )
            return (data, response)
        } catch {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000.0)
            addHttpBreadcrumb(
                method: "POST",
                url: request.url,
                statusCode: nil,
                traceId: nil,
                durationMs: durationMs,
                requestBodySize: requestBodySize,
                responseBodySize: nil,
                followRedirect: true,
                error: error
            )
            SentryHelper.logError(error, context: [
                "http": [
                    "method": "POST",
                    "path": "/frontegg/oauth/authorize/silent"
                ]
            ])
            throw error
        }
    }
    
    internal func silentAuthorizeWithToken(
        refreshToken: String,
        timeout: Int = Api.DEFAULT_TIMEOUT
    ) async throws -> (Data, URLResponse) {
        // Use POST /oauth/token with grant_type=refresh_token
        let (data, response) = try await postRequest(path: "oauth/token", body: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ], timeout: timeout)
        
        TraceIdLogger.shared.extractAndLogTraceId(from: response)
        return (data, response)
    }

    
    internal func authroizeWithTokens(refreshToken:String, deviceTokenCookie:String? = nil) async throws -> AuthResponse {
        // Use POST /oauth/token with grant_type=refresh_token
        let (data, _) = try await FronteggAuth.shared.api.silentAuthorize(refreshToken: refreshToken)
        
        // Decode and return the AuthResponse
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }
    
    internal func refreshToken(refreshToken: String, tenantId: String? = nil, accessToken: String? = nil) async throws -> AuthResponse {
        // If tenantId is provided, use the new refresh endpoint that supports per-tenant sessions
        if let unwrappedTenantId = tenantId {
            self.logger.info("Refreshing token with tenantId: \(unwrappedTenantId) (refresh token length: \(refreshToken.count))")
            let refreshTokenCookie = "\(self.cookieName)=\(refreshToken)"
            
            var headers: [String: String] = [
                "Cookie": refreshTokenCookie,
                "frontegg-vendor-host": self.baseUrl
            ]
            
            // Include access token in Authorization header if provided
            // This is needed for tenant-specific refresh to work correctly
            if let accessToken = accessToken {
                headers["Authorization"] = "Bearer \(accessToken)"
                self.logger.info("Including access token in Authorization header for tenant-specific refresh")
            }
            
            let (data, response) = try await postRequest(
                path: "identity/resources/auth/v1/user/token/refresh",
                body: ["tenantId": unwrappedTenantId],
                additionalHeaders: headers,
                timeout: 5
            )
            
            if let res = response as? HTTPURLResponse {
                if res.statusCode == 401 {
                    let responseString = String(data: data, encoding: .utf8) ?? "no response body"
                    self.logger.error("failed to refresh token with tenantId (401), error: \(responseString)")
                    
                    SentryHelper.logMessage("Api: failed to refresh token, error: \(responseString)", level: .error, context: [
                        "api": [
                            "endpoint": "identity/resources/auth/v1/user/token/refresh",
                            "method": "POST",
                            "statusCode": res.statusCode,
                            "hasTenantId": true,
                            "tenantId": unwrappedTenantId
                        ],
                        "error": [
                            "type": "refresh_token_failed",
                            "response": responseString
                        ]
                    ])
                    
                    throw FronteggError.authError(.failedToRefreshToken(responseString))
                } else if res.statusCode != 200 {
                    let responseString = String(data: data, encoding: .utf8) ?? "no response body"
                    self.logger.error("failed to refresh token with tenantId, status: \(res.statusCode), error: \(responseString)")
                    
                    SentryHelper.logMessage("Api: failed to refresh token, status: \(res.statusCode), error: \(responseString)", level: .error, context: [
                        "api": [
                            "endpoint": "identity/resources/auth/v1/user/token/refresh",
                            "method": "POST",
                            "statusCode": res.statusCode,
                            "hasTenantId": true,
                            "tenantId": unwrappedTenantId
                        ],
                        "error": [
                            "type": "refresh_token_failed",
                            "response": responseString
                        ]
                    ])
                    
                    throw FronteggError.authError(.failedToRefreshToken(responseString))
                } else {
                    self.logger.info("Refresh with tenantId response: status=\(res.statusCode)")
                }
            }
            
            do {
                let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
                self.logger.info("Successfully decoded AuthResponse from refresh with tenantId")
                return authResponse
            } catch {
                self.logger.error("Failed to decode AuthResponse from refresh with tenantId: \(error)")
                
                SentryHelper.logError(error, context: [
                    "api": [
                        "endpoint": "identity/resources/auth/v1/user/token/refresh",
                        "method": "POST",
                        "hasTenantId": true,
                        "tenantId": unwrappedTenantId
                    ],
                    "error": [
                        "type": "decode_error",
                        "stage": "refresh_token_response"
                    ]
                ])
                
                throw error
            }
        } else {
            let (data, response) = try await postRequest(path: "oauth/token", body: [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
            ], timeout: 5)
            
            if let res = response as? HTTPURLResponse {
                if res.statusCode == 401 {
                    let responseString = String(data: data, encoding: .utf8) ?? "no response body"
                    self.logger.error("failed to refresh token (401), error: \(responseString)")
                    
                    SentryHelper.logMessage("Api: failed to refresh token, error: \(responseString)", level: .error, context: [
                        "api": [
                            "endpoint": "oauth/token",
                            "method": "POST",
                            "statusCode": res.statusCode,
                            "grantType": "refresh_token"
                        ],
                        "error": [
                            "type": "refresh_token_failed",
                            "response": responseString
                        ]
                    ])
                    
                    throw FronteggError.authError(.failedToRefreshToken(responseString))
                } else if res.statusCode != 200 {
                    let responseString = String(data: data, encoding: .utf8) ?? "no response body"
                    self.logger.error("failed to refresh token, status: \(res.statusCode), error: \(responseString)")
                    
                    SentryHelper.logMessage("Api: failed to refresh token, status: \(res.statusCode), error: \(responseString)", level: .error, context: [
                        "api": [
                            "endpoint": "oauth/token",
                            "method": "POST",
                            "statusCode": res.statusCode,
                            "grantType": "refresh_token"
                        ],
                        "error": [
                            "type": "refresh_token_failed",
                            "response": responseString
                        ]
                    ])
                    
                    throw FronteggError.authError(.failedToRefreshToken(responseString))
                } else {
                    self.logger.info("OAuth refresh response: status=\(res.statusCode)")
                }
            }
            
            do {
                let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
                self.logger.info("Successfully decoded AuthResponse from OAuth refresh")
                return authResponse
            } catch {
                self.logger.error("Failed to decode AuthResponse: \(error)")
                
                SentryHelper.logError(error, context: [
                    "api": [
                        "endpoint": "oauth/token",
                        "method": "POST",
                        "grantType": "refresh_token"
                    ],
                    "error": [
                        "type": "decode_error",
                        "stage": "refresh_token_response"
                    ]
                ])
                
                throw error
            }
        }
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
                                codeVerifier: String?) async -> (AuthResponse?, FronteggError?) {
        do {
            var body: [String: Any] = [
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": redirectUrl,
            ]
            
            // Only include code_verifier if it's provided (for PKCE flow)
            // Magic link flow doesn't use PKCE, so code_verifier should be nil
            if let codeVerifier = codeVerifier {
                body["code_verifier"] = codeVerifier
            }
                        
            let (data, _) = try await postRequest(path: "oauth/token", body: body)
            
            if let responseString = String(data: data, encoding: .utf8),
               responseString.contains("\"errors\"") || responseString.contains("\"error\"") {
                return (nil, FronteggError.authError(.other(NSError(domain: "FronteggAuth", code: 400, userInfo: [NSLocalizedDescriptionKey: responseString]))))
            }
            
            return (try JSONDecoder().decode(AuthResponse.self, from: data), nil)
        } catch {
            return (nil, FronteggError.authError(.couldNotExchangeToken(error.localizedDescription)))
        }
    }
    
    internal func me(accessToken: String) async throws -> User? {
        let (meData, _) = try await getRequest(path: "identity/resources/users/v2/me", accessToken: accessToken)
        
        var meObj = try JSONSerialization.jsonObject(with: meData, options: [])  as! [String: Any]
        
        let (tenantsData, _) = try await getRequest(path: "identity/resources/users/v3/me/tenants", accessToken: accessToken)
        
        let tenantsObj = try JSONSerialization.jsonObject(with: tenantsData, options: [])  as! [String: Any]
        
        if let tenants = tenantsObj["tenants"] as? [[String: Any]] {
            self.logger.info("Found \(tenants.count) tenant(s) from API")
            for tenant in tenants {
                if let name = tenant["name"] as? String, let id = tenant["id"] as? String {
                    self.logger.info("  - Tenant: \(name) (ID: \(id))")
                }
            }
        } else {
            self.logger.warning("No tenants array found in API response: \(tenantsObj)")
        }
        
        meObj["tenants"] = tenantsObj["tenants"]
        meObj["activeTenant"] = tenantsObj["activeTenant"]
        
        let mergedData = try JSONSerialization.data(withJSONObject: meObj)
        
        
        return try JSONDecoder().decode(User.self, from: mergedData)
    }
    
    public func switchTenant(tenantId: String, accessToken: String? = nil) async throws -> Void {
        var tokenToUse = accessToken
        if tokenToUse == nil {
            if let currentToken = try? credentialManager.get(key: KeychainKeys.accessToken.rawValue) {
                tokenToUse = currentToken
            }
        }
        
        let urlStr = "\(self.baseUrl)/identity/resources/users/v1/tenant"
        guard let url = URL(string: urlStr) else {
            throw ApiError.invalidUrl("invalid url: \(urlStr)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(self.baseUrl, forHTTPHeaderField: "Origin")
        if let applicationId = self.applicationId {
            request.setValue(applicationId, forHTTPHeaderField: "frontegg-requested-application-id")
        }
        if let token = tokenToUse {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            self.logger.warning("No access token available for switchTenant request")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["tenantId": tenantId])
        
        request.timeoutInterval = TimeInterval(10)
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = TimeInterval(10)
        config.timeoutIntervalForResource = TimeInterval(10)
        config.waitsForConnectivity = false
        
        let session = URLSession(configuration: config)
        let (data, response) = try await session.data(for: request)
        TraceIdLogger.shared.extractAndLogTraceId(from: response)
        
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 200 || httpResponse.statusCode == 204 {
                self.logger.info("Tenant switched successfully to: \(tenantId)")
            } else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                self.logger.error("Failed to switch tenant. Status: \(httpResponse.statusCode), Response: \(errorMessage)")
                throw FronteggError.authError(.failedToSwitchTenant)
            }
        }
    }
    
    internal func logout(accessToken: String?, refreshToken: String?) async {
        if refreshToken == nil {
            self.logger.warning("Cannot logout on server: refreshToken is nil. Session may remain active on server.")
            return
        }
        
        do {
            let refreshTokenCookie = "\(self.cookieName)=\(refreshToken!)"
            let (_, response) = try await postRequest(
                path: "oauth/logout/token",
                body: [:],
                additionalHeaders: ["Cookie": refreshTokenCookie]
            )
            
            if let res = response as? HTTPURLResponse {
                if res.statusCode == 200 || res.statusCode == 204 {
                self.logger.info("logged out successfully")
                } else if res.statusCode == 401 {
                self.logger.info("Already logged out")
                } else {
                    self.logger.warning("Logout returned unexpected status code: \(res.statusCode). Session may remain active on server.")
                }
            }
        } catch {
            self.logger.warning("API logout failed: \(error.localizedDescription). Proceeding with local cleanup.")
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
              let refreshTokenCookie = cookies.0 else {
            if let httpError = String(data: postloginResponseData, encoding: .utf8) {
                throw FronteggError.authError(.failedToAuthenticateWithPasskeys(httpError))
            } else {
                throw FronteggError.authError(.failedToAuthenticateWithPasskeys("No cookies returns from postLogin request"))
            }
        }
        
        // Extract token value from cookie string "name=value"
        let cookieParts = refreshTokenCookie.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard cookieParts.count == 2 else {
            throw FronteggError.authError(.failedToAuthenticateWithPasskeys("Invalid refresh token cookie format"))
        }
        let refreshToken = String(cookieParts[1])
        
        // Silent authorize with the extracted token
        let (data, _) = try await FronteggAuth.shared.api.silentAuthorize(refreshToken: refreshToken)
        
        // Decode and return the AuthResponse
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }
    
    public func getSocialLoginConfig() async throws -> SocialLoginConfig {
        let (jsonData, _) = try await FronteggAuth.shared.api.getRequest(path: "/frontegg/identity/resources/sso/v2", accessToken: nil)
        let options = try JSONDecoder().decode([SocialLoginOption].self, from: jsonData)
        
        return SocialLoginConfig(options: options)
    }
    public func getCustomSocialLoginConfig() async throws -> CustomSocialLoginProvidersResponse {
        let (jsonData, _) = try await FronteggAuth.shared.api.getRequest(path: "/identity/resources/sso/custom/v1", accessToken: nil)
        return try JSONDecoder().decode(CustomSocialLoginProvidersResponse.self, from: jsonData)
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
              let refreshTokenCookie = cookies.0 else {
            throw FronteggError.authError(.invalidPasskeysRequest)
        }
        
        // Extract token value from cookie string "name=value"
        let cookieParts = refreshTokenCookie.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard cookieParts.count == 2 else {
            throw FronteggError.authError(.invalidPasskeysRequest)
        }
        let refreshToken = String(cookieParts[1])
        
        // Silent authorize with the extracted token
        let (data, _) = try await FronteggAuth.shared.api.silentAuthorize(refreshToken: refreshToken)
        
        // Decode and return the AuthResponse
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }
    
    
    internal func getFeatureFlags() async throws -> String {
        let (stringData, _) = try await FronteggAuth.shared.api.getRequest(path: "/flags", accessToken: nil)
        
        return String(data: stringData, encoding: .utf8) ?? ""
    }
}

extension HTTPURLResponse {
    var isSuccess: Bool {
        return (200...299).contains(self.statusCode)
    }
}
