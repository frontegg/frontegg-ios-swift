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
    let loginWithSSO: Bool
    let lateInit: Bool
    let logLevel: LogLevel
    let payload: Payload
    let keepUserLoggedInAfterReinstall: Bool
    let useAsWebAuthenticationForAppleLogin: Bool

    enum CodingKeys: CodingKey {
        case keychainService
        case embeddedMode
        case loginWithSocialLogin
        case loginWithSSO
        case lateInit
        case logLevel
        case keepUserLoggedInAfterReinstall
        case useAsWebAuthenticationForAppleLogin
    }

    init(
        keychainService: String = "frontegg",
        embeddedMode: Bool = true,
        loginWithSocialLogin: Bool = true,
        loginWithSSO: Bool = false,
        lateInit: Bool = false,
        logLevel: LogLevel = .warn,
        payload: Payload,
        keepUserLoggedInAfterReinstall: Bool,
        useAsWebAuthenticationForAppleLogin: Bool = false
    ) {
        self.keychainService = keychainService
        self.embeddedMode = embeddedMode
        self.loginWithSocialLogin = loginWithSocialLogin
        self.loginWithSSO = loginWithSSO
        self.lateInit = lateInit
        self.logLevel = logLevel
        self.payload = payload
        self.keepUserLoggedInAfterReinstall = keepUserLoggedInAfterReinstall
        self.useAsWebAuthenticationForAppleLogin = useAsWebAuthenticationForAppleLogin
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let keychainService = try container.decodeIfPresent(String.self, forKey: .keychainService)
        self.keychainService = keychainService ?? "frontegg"

        let embeddedMode = try container.decodeIfPresent(Bool.self, forKey: .embeddedMode)
        self.embeddedMode = embeddedMode ?? true

        let socialLogin = try container.decodeIfPresent(Bool.self, forKey: .loginWithSocialLogin)
        self.loginWithSocialLogin = socialLogin ?? true

        let ssoLogin = try container.decodeIfPresent(Bool.self, forKey: .loginWithSSO)
        self.loginWithSSO = ssoLogin ?? false

        let lateInit = try container.decodeIfPresent(Bool.self, forKey: .lateInit)
        self.lateInit = lateInit ?? false

        let logLevel = try container.decodeIfPresent(LogLevel.self, forKey: .logLevel)
        self.logLevel = logLevel ?? .warn
        
        let keepUserLoggedInAfterReinstall = try container.decodeIfPresent(Bool.self, forKey: .keepUserLoggedInAfterReinstall)
        self.keepUserLoggedInAfterReinstall = keepUserLoggedInAfterReinstall ?? true
        
        let useAsWebAuthenticationForAppleLogin = try container.decodeIfPresent(Bool.self, forKey: .useAsWebAuthenticationForAppleLogin)
        self.useAsWebAuthenticationForAppleLogin = useAsWebAuthenticationForAppleLogin ?? false
        
        do {
            self.payload = try Payload(from: decoder)
        } catch {
            if lateInit != true {
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

extension Logger.Level {

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
