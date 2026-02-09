//
//  FronteggPlist.swift
//
//
//  Created by Nick Hagi on 25/07/2024.
//

import Foundation



// MARK: - Frontegg Plist
struct FronteggPlist: Decodable, Equatable {
    
    let keychainService: String
    let embeddedMode: Bool
    let loginWithSocialLogin: Bool
    let handleLoginWithCustomSocialLoginProvider: Bool
    let handleLoginWithSocialProvider: Bool
    let loginWithSSO: Bool
    let loginWithCustomSSO: Bool
    let lateInit: Bool
    let logLevel: LogLevel
    let payload: Payload
    let keepUserLoggedInAfterReinstall: Bool
    let useAsWebAuthenticationForAppleLogin: Bool
    let shouldSuggestSavePassword:Bool
    var backgroundColor: String? = nil
    var cookieRegex: String? = nil
    let deleteCookieForHostOnly: Bool
    let enableOfflineMode: Bool
    let useLegacySocialLoginFlow: Bool
    let enableSessionPerTenant: Bool
    var networkMonitoringInterval: TimeInterval
    let enableSentryLogging: Bool
    let sentryMaxQueueSize: Int
    /// Account (tenant) alias for login-per-account (custom login box). When set, authorize URL includes organization=<alias>. Omit or leave empty for standard login.
    var loginOrganizationAlias: String? = nil

    enum CodingKeys: CodingKey {
        case keychainService
        case embeddedMode
        case loginWithSocialLogin
        case handleLoginWithCustomSocialLoginProvider
        case handleLoginWithSocialProvider
        case loginWithSSO
        case loginWithCustomSSO
        case lateInit
        case logLevel
        case keepUserLoggedInAfterReinstall
        case useAsWebAuthenticationForAppleLogin
        case shouldSuggestSavePassword
        case backgroundColor
        case cookieRegex
        case deleteCookieForHostOnly
        case enableOfflineMode
        case useLegacySocialLoginFlow
        case enableSessionPerTenant
        case networkMonitoringInterval
        case enableSentryLogging
        case sentryMaxQueueSize
        case loginOrganizationAlias
    }

    init(
        keychainService: String = "frontegg",
        embeddedMode: Bool = true,
        loginWithSocialLogin: Bool = true,
        handleLoginWithCustomSocialLoginProvider: Bool = true,
        handleLoginWithSocialProvider: Bool = true,
        loginWithSSO: Bool = false,
        loginWithCustomSSO: Bool = false,
        lateInit: Bool = false,
        logLevel: LogLevel = .warn,
        payload: Payload,
        keepUserLoggedInAfterReinstall: Bool,
        useAsWebAuthenticationForAppleLogin: Bool = true,
        shouldSuggestSavePassword: Bool = false,
        backgroundColor: String? = nil,
        cookieRegex: String? = nil,
        deleteCookieForHostOnly: Bool = true,
        enableOfflineMode: Bool = false,
        useLegacySocialLoginFlow: Bool = false,
        enableSessionPerTenant: Bool = false,
        networkMonitoringInterval: TimeInterval = 10,
        enableSentryLogging: Bool = true,
        sentryMaxQueueSize: Int = 30,
        loginOrganizationAlias: String? = nil
    ) {
        self.keychainService = keychainService
        self.embeddedMode = embeddedMode
        self.loginWithSocialLogin = loginWithSocialLogin
        self.handleLoginWithCustomSocialLoginProvider = handleLoginWithCustomSocialLoginProvider
        self.handleLoginWithSocialProvider = handleLoginWithSocialProvider
        self.loginWithSSO = loginWithSSO
        self.loginWithCustomSSO = loginWithCustomSSO
        self.lateInit = lateInit
        self.logLevel = logLevel
        self.payload = payload
        self.keepUserLoggedInAfterReinstall = keepUserLoggedInAfterReinstall
        self.useAsWebAuthenticationForAppleLogin = useAsWebAuthenticationForAppleLogin
        self.shouldSuggestSavePassword = shouldSuggestSavePassword
        self.backgroundColor = backgroundColor
        self.cookieRegex = cookieRegex
        self.deleteCookieForHostOnly = deleteCookieForHostOnly
        self.enableOfflineMode = enableOfflineMode
        self.useLegacySocialLoginFlow = useLegacySocialLoginFlow
        self.enableSessionPerTenant = enableSessionPerTenant
        self.networkMonitoringInterval = networkMonitoringInterval
        self.enableSentryLogging = enableSentryLogging
        self.sentryMaxQueueSize = sentryMaxQueueSize
        self.loginOrganizationAlias = loginOrganizationAlias
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let keychainService = try container.decodeIfPresent(String.self, forKey: .keychainService)
        self.keychainService = keychainService ?? "frontegg"

        let embeddedMode = try container.decodeIfPresent(Bool.self, forKey: .embeddedMode)
        self.embeddedMode = embeddedMode ?? true

        let socialLogin = try container.decodeIfPresent(Bool.self, forKey: .loginWithSocialLogin)
        self.loginWithSocialLogin = socialLogin ?? true

        let customSocialProviderLogin = try container.decodeIfPresent(Bool.self, forKey: .handleLoginWithCustomSocialLoginProvider)
        self.handleLoginWithCustomSocialLoginProvider = customSocialProviderLogin ?? true

        let socialProviderLogin = try container.decodeIfPresent(Bool.self, forKey: .handleLoginWithSocialProvider)
        self.handleLoginWithSocialProvider = socialProviderLogin ?? true

        let ssoLogin = try container.decodeIfPresent(Bool.self, forKey: .loginWithSSO)
        self.loginWithSSO = ssoLogin ?? false
        
        let customSsoLogin = try container.decodeIfPresent(Bool.self, forKey: .loginWithCustomSSO)
        self.loginWithCustomSSO = customSsoLogin ?? false

        let lateInit = try container.decodeIfPresent(Bool.self, forKey: .lateInit)
        self.lateInit = lateInit ?? false

        let logLevel = try container.decodeIfPresent(LogLevel.self, forKey: .logLevel)
        self.logLevel = logLevel ?? .warn
        
        let keepUserLoggedInAfterReinstall = try container.decodeIfPresent(Bool.self, forKey: .keepUserLoggedInAfterReinstall)
        self.keepUserLoggedInAfterReinstall = keepUserLoggedInAfterReinstall ?? true
        
        let useAsWebAuthenticationForAppleLogin = try container.decodeIfPresent(Bool.self, forKey: .useAsWebAuthenticationForAppleLogin)
        self.useAsWebAuthenticationForAppleLogin = useAsWebAuthenticationForAppleLogin ?? false
        
        let shouldSuggestSavePassword = try container.decodeIfPresent(Bool.self, forKey: .shouldSuggestSavePassword)
        self.shouldSuggestSavePassword = shouldSuggestSavePassword ?? false

        let backgroundColor = try container.decodeIfPresent(String.self, forKey: .backgroundColor)
        self.backgroundColor = backgroundColor
        
        let cookieRegex = try container.decodeIfPresent(String.self, forKey: .cookieRegex)
        self.cookieRegex = cookieRegex
        
        let deleteCookieForHostOnly = try container.decodeIfPresent(Bool.self, forKey: .deleteCookieForHostOnly)
        self.deleteCookieForHostOnly = deleteCookieForHostOnly ?? true
        
        let enableOfflineMode = try container.decodeIfPresent(Bool.self, forKey: .enableOfflineMode)
        self.enableOfflineMode = enableOfflineMode ?? false
        
        let useLegacySocialLoginFlow = try container.decodeIfPresent(Bool.self, forKey: .useLegacySocialLoginFlow)
        self.useLegacySocialLoginFlow = useLegacySocialLoginFlow ?? false
        
        let enableSessionPerTenant = try container.decodeIfPresent(Bool.self, forKey: .enableSessionPerTenant)
        self.enableSessionPerTenant = enableSessionPerTenant ?? false
        
        let networkMonitoringInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .networkMonitoringInterval)
        self.networkMonitoringInterval = networkMonitoringInterval ?? 10
        
        let enableSentryLogging = try container.decodeIfPresent(Bool.self, forKey: .enableSentryLogging)
        self.enableSentryLogging = enableSentryLogging ?? true
        
        let sentryMaxQueueSize = try container.decodeIfPresent(Int.self, forKey: .sentryMaxQueueSize)
        self.sentryMaxQueueSize = sentryMaxQueueSize ?? 30

        let loginOrganizationAlias = try container.decodeIfPresent(String.self, forKey: .loginOrganizationAlias)
        self.loginOrganizationAlias = loginOrganizationAlias.flatMap { $0.isEmpty ? nil : $0 }
        
        do {
            self.payload = try Payload(from: decoder)
        } catch {
            if !self.lateInit {
                throw error
            }
            
            let emptyPayload = try JSONSerialization.data(withJSONObject: ["baseUrl":"", "clientId":""], options: [])
            let defaultLateInitPayload = try JSONDecoder().decode(Payload.self, from: emptyPayload)
            self.payload = defaultLateInitPayload
        }
    }
}

// MARK: - Payload
extension FronteggPlist {

    enum Payload: Equatable {

        case singleRegion(SingleRegionConfig)
        case multiRegion(MultiRegionConfig)
    }
}

extension FronteggPlist.Payload: Decodable {

    init(from decoder: any Decoder) throws {
        do {
            let multiRegion = try decoder.singleValueContainer().decode(MultiRegionConfig.self)
            self = .multiRegion(multiRegion)
        } catch {
            let singleRegion = try decoder.singleValueContainer().decode(SingleRegionConfig.self)
            self = .singleRegion(singleRegion)
        }
    }
}

// MARK: - LogLevel
extension FronteggPlist {

    enum LogLevel: String, Decodable {

        case trace
        case debug
        case info
        case warn
        case error
        case critical
    }
}

extension FeLogger.Level {

    init(with logLevel: FronteggPlist.LogLevel) {
        switch logLevel {
        case .trace: self = .trace
        case .debug: self = .debug
        case .info: self = .info
        case .warn: self = .warning
        case .error: self = .error
        case .critical: self = .critical
        }
    }
}
