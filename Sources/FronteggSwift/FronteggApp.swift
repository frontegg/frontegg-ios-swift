//
//  FronteggApp.swift
//  
//
//  Created by David Frontegg on 22/12/2022.
//

import Foundation
import UIKit

/// Controls how the SDK presents OAuth failures to the user.
public enum FronteggOAuthErrorPresentation: Equatable {
    /// The SDK shows its built-in top toast with the formatted error message.
    case toast
    /// The SDK suppresses its built-in toast and forwards the failure to
    /// `oauthErrorDelegate` so the app can render its own UI.
    case delegate
}

/// Identifies the OAuth flow that produced an error.
public enum FronteggOAuthFlow: Equatable {
    /// Standard login and hosted login callbacks.
    case login
    /// Social login, such as Google or GitHub.
    case socialLogin
    /// Standard SSO flows.
    case sso
    /// Custom SSO flows.
    case customSSO
    /// Sign in with Apple.
    case apple
    /// MFA verification flows.
    case mfa
    /// Step-up authentication flows.
    case stepUp
    /// Verification or email confirmation flows.
    case verification
}

/// Carries the SDK's normalized OAuth failure payload for custom presentation.
public struct FronteggOAuthErrorContext {
    /// The user-facing message the SDK would display in toast mode.
    public let displayMessage: String
    /// The raw OAuth error code, when available.
    public let errorCode: String?
    /// The decoded OAuth error description, when available.
    public let errorDescription: String?
    /// The SDK error object for programmatic inspection.
    public let error: FronteggError
    /// The OAuth flow that failed.
    public let flow: FronteggOAuthFlow
    /// Whether the failure happened while the SDK was configured for embedded mode.
    public let embeddedMode: Bool

    /// Creates an OAuth error context for app-controlled rendering.
    public init(
        displayMessage: String,
        errorCode: String?,
        errorDescription: String?,
        error: FronteggError,
        flow: FronteggOAuthFlow,
        embeddedMode: Bool
    ) {
        self.displayMessage = displayMessage
        self.errorCode = errorCode
        self.errorDescription = errorDescription
        self.error = error
        self.flow = flow
        self.embeddedMode = embeddedMode
    }
}

/// Implement this protocol to render OAuth failures yourself.
///
/// Assign the delegate through `FronteggApp.oauthErrorDelegate` and set
/// `FronteggApp.oauthErrorPresentation = .delegate`.
///
/// The callback is delivered on the main thread. User-cancelled OAuth flows are
/// not reported.
public protocol FronteggOAuthErrorDelegate: AnyObject {
    /// Called when the SDK wants the host app to present an OAuth failure.
    ///
    /// - Parameter context: The normalized OAuth failure payload, including the
    ///   user-facing message, structured error fields, and flow metadata.
    func fronteggSDK(didReceiveOAuthError context: FronteggOAuthErrorContext)
}

final class FronteggWeakOAuthErrorDelegateBox {
    weak var value: FronteggOAuthErrorDelegate?
}

enum FronteggOAuthErrorRuntimeSettings {
    static var presentation: FronteggOAuthErrorPresentation = .toast
    static let delegateBox = FronteggWeakOAuthErrorDelegateBox()
}

public class FronteggApp {
    
    public static let shared = FronteggApp()
    
    public var auth: FronteggAuth
    public var baseUrl: String = ""
    public var clientId: String = ""
    public var applicationId: String? = nil
    public var bundleIdentifier: String = ""
    public var embeddedMode: Bool = true
    public var handleLoginWithSocialLogin:Bool = true
    public var handleLoginWithSSO:Bool = false
    public var handleLoginWithCustomSSO:Bool = false
    public var handleLoginWithCustomSocialLoginProvider:Bool = true
    public var handleLoginWithSocialProvider:Bool = true
    public var backgroundColor: UIColor? = nil
    public var entitlementsEnabled: Bool = false
    /// Convenience alias over `FeLogger.delegate`.
    ///
    /// Set `FeLogger.delegate` directly if you need to capture logs before
    /// `FronteggApp.shared` is initialized. The delegate is called
    /// synchronously on the originating thread and is stored weakly.
    public var loggerDelegate: FronteggLoggerDelegate? {
        get { FeLogger.delegate }
        set { FeLogger.delegate = newValue }
    }
    /// Controls how the SDK presents OAuth failures.
    ///
    /// Defaults to `.toast`. Set to `.delegate` to suppress the built-in SDK
    /// toast and route failures to `oauthErrorDelegate` instead.
    public var oauthErrorPresentation: FronteggOAuthErrorPresentation {
        get { FronteggOAuthErrorRuntimeSettings.presentation }
        set { FronteggOAuthErrorRuntimeSettings.presentation = newValue }
    }
    /// Delegate for app-controlled OAuth failure rendering.
    ///
    /// The delegate is stored weakly and is called on the main thread when
    /// `oauthErrorPresentation` is set to `.delegate`. Completion handlers for
    /// the underlying auth flow still run as usual. User-cancelled OAuth flows
    /// are not reported.
    public var oauthErrorDelegate: FronteggOAuthErrorDelegate? {
        get { FronteggOAuthErrorRuntimeSettings.delegateBox.value }
        set { FronteggOAuthErrorRuntimeSettings.delegateBox.value = newValue }
    }

    /// Account (tenant) alias for login-per-account (custom login box). When set, the authorize URL includes `organization=<alias>` so Frontegg routes the user to that account's login experience. Set from your app (e.g. from subdomain or query param) before calling login. Note: `switchTenant` is not supported between accounts that use custom login boxes.
    public var loginOrganizationAlias: String? = nil

    /* force consent when authenticate with social login */
    public var shouldPromptSocialLoginConsent:Bool = true
    
    public var shouldSuggestSavePassword:Bool = false
    
    
    public var regionData: [RegionConfig] = []
    let credentialManager: CredentialManager
    let logger = getLogger("FronteggApp")
    let debugConfigurationChecker = DebugConfigurationChecker()

    init() {
        let config: FronteggPlist
        do {
            config = try PlistHelper.fronteggConfig()
        } catch {
            fatalError(FronteggError.configError(.couldNotLoadPlist(error.localizedDescription)).localizedDescription)
        }

        debugConfigurationChecker.runChecks()
        
        // Initialize Sentry if enabled in config
        SentryHelper.initialize()
        
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            fatalError(FronteggError.configError(.couldNotGetBundleID(Bundle.main.bundlePath)).localizedDescription)
        }

        self.embeddedMode = config.embeddedMode
        self.credentialManager = CredentialManager(serviceKey: config.keychainService)
        self.bundleIdentifier = bundleIdentifier
        self.handleLoginWithSocialLogin = config.loginWithSocialLogin
        self.handleLoginWithSSO = config.loginWithSSO
        self.handleLoginWithCustomSSO = config.loginWithCustomSSO
        self.shouldSuggestSavePassword = config.shouldSuggestSavePassword
        self.handleLoginWithSocialProvider = config.handleLoginWithSocialProvider
        self.handleLoginWithCustomSocialLoginProvider = config.handleLoginWithCustomSocialLoginProvider
        self.backgroundColor = UIColor(named: config.backgroundColor ?? "#FFFFFF") ?? .white
        self.loginOrganizationAlias = config.loginOrganizationAlias
        self.entitlementsEnabled = config.entitlementsEnabled

        if FronteggApp.clearKeychain(config: config) {
            self.credentialManager.clear()
        }
        /**
         lateInit used for react-native and ionic-capacitor initialization
         */
        if config.lateInit {
            self.auth = FronteggAuth(
                baseUrl: self.baseUrl,
                clientId: self.clientId,
                applicationId: self.applicationId,
                credentialManager: self.credentialManager,
                isRegional: false,
                regionData: self.regionData,
                embeddedMode: self.embeddedMode,
                isLateInit: true,
                entitlementsEnabled: self.entitlementsEnabled
            )
            return
        }

        switch config.payload {
        case let .multiRegion(config):
            logger.info("Regional frontegg initialization")
            self.regionData = config.regions

            self.auth = FronteggAuth(
                baseUrl: self.baseUrl,
                clientId: self.clientId,
                applicationId: self.applicationId,
                credentialManager: self.credentialManager,
                isRegional: true,
                regionData: self.regionData,
                embeddedMode: self.embeddedMode,
                entitlementsEnabled: self.entitlementsEnabled
            )

            if let config = self.auth.selectedRegion {
                self.baseUrl = config.baseUrl
                self.clientId = config.clientId
                self.applicationId = config.applicationId
                self.auth.reinitWithRegion(config: config, entitlementsEnabled: self.entitlementsEnabled)

                SentryHelper.setBaseUrl(self.baseUrl)
                SentryHelper.setClientId(self.clientId)
                logger.info("Frontegg Initialized succcessfully (region: \(config.key))")
                return;
            } else {
                // skip automatic authorize for regional config
                self.auth.setInitializing(false)
                self.auth.setIsLoading(false)
                self.auth.setShowLoader(false)
            }

        case let .singleRegion(config):
            logger.info("Standard frontegg initialization")

            self.baseUrl = config.baseUrl
            self.clientId = config.clientId
            self.applicationId = config.applicationId

            self.auth = FronteggAuth(
                baseUrl: self.baseUrl,
                clientId: self.clientId,
                applicationId: self.applicationId,
                credentialManager: self.credentialManager,
                isRegional: false,
                regionData: [],
                embeddedMode: self.embeddedMode,
                entitlementsEnabled: self.entitlementsEnabled
            )

            SentryHelper.setBaseUrl(self.baseUrl)
            SentryHelper.setClientId(self.clientId)
            logger.info("Frontegg Initialized succcessfully")
        }
    }
 
    public func didFinishLaunchingWithOptions(){
        logger.info("Frontegg baseURL: \(self.baseUrl)")
    }

#if DEBUG
    @MainActor
    public func resetForTesting(baseUrlOverride: String? = nil) async {
        await auth.resetForTesting(baseUrlOverride: baseUrlOverride)
    }

    public func configureTestingNetworkPathAvailability(_ available: Bool?) {
        auth.setTestNetworkPathAvailabilityOverride(available)
    }

    /// Overrides the `enableOfflineMode` plist setting for E2E testing.
    /// Pass `nil` to clear the override and use the plist default.
    /// Must be called **before** `manualInit` so `initializeSubscriptions` reads the override.
    public func configureTestingOfflineMode(_ enabled: Bool?) {
        guard var config = try? PlistHelper.fronteggConfig() else { return }
        if let enabled {
            let overridden = FronteggPlist(
                keychainService: config.keychainService,
                embeddedMode: config.embeddedMode,
                loginWithSocialLogin: config.loginWithSocialLogin,
                handleLoginWithCustomSocialLoginProvider: config.handleLoginWithCustomSocialLoginProvider,
                handleLoginWithSocialProvider: config.handleLoginWithSocialProvider,
                loginWithSSO: config.loginWithSSO,
                loginWithCustomSSO: config.loginWithCustomSSO,
                lateInit: config.lateInit,
                logLevel: config.logLevel,
                payload: config.payload,
                keepUserLoggedInAfterReinstall: config.keepUserLoggedInAfterReinstall,
                useAsWebAuthenticationForAppleLogin: config.useAsWebAuthenticationForAppleLogin,
                shouldSuggestSavePassword: config.shouldSuggestSavePassword,
                backgroundColor: config.backgroundColor,
                cookieRegex: config.cookieRegex,
                deleteCookieForHostOnly: config.deleteCookieForHostOnly,
                enableOfflineMode: enabled,
                disableAutoRefresh: config.disableAutoRefresh,
                useLegacySocialLoginFlow: config.useLegacySocialLoginFlow,
                enableSessionPerTenant: config.enableSessionPerTenant,
                networkMonitoringInterval: config.networkMonitoringInterval,
                enableSentryLogging: config.enableSentryLogging,
                sentryMaxQueueSize: config.sentryMaxQueueSize,
                loginOrganizationAlias: config.loginOrganizationAlias,
                entitlementsEnabled: config.entitlementsEnabled
            )
            PlistHelper.testConfigOverride = overridden
        } else {
            PlistHelper.testConfigOverride = nil
        }
    }
#endif
    
    public func manualInit(
            baseUrl: String,
            cliendId: String,
            applicationId: String? = nil,
            handleLoginWithSocialLogin: Bool = true,
            handleLoginWithSSO:Bool = false,
            handleLoginWithCustomSSO:Bool = false,
            handleLoginWithCustomSocialLoginProvider:Bool = true,
            handleLoginWithSocialProvider:Bool = true,
            entitlementsEnabled: Bool = false
    ) {
        self.baseUrl = baseUrl
        self.clientId = cliendId
        self.applicationId = applicationId

        SentryHelper.setBaseUrl(self.baseUrl)
        SentryHelper.setClientId(self.clientId)

        self.handleLoginWithSocialLogin = handleLoginWithSocialLogin
        self.handleLoginWithSSO = handleLoginWithSSO
        self.handleLoginWithCustomSSO = handleLoginWithCustomSSO
        self.handleLoginWithCustomSocialLoginProvider = handleLoginWithCustomSocialLoginProvider
        self.handleLoginWithSocialProvider = handleLoginWithSocialProvider
        self.entitlementsEnabled = entitlementsEnabled

        self.auth.manualInit(baseUrl: baseUrl, clientId: cliendId, applicationId: applicationId, entitlementsEnabled: entitlementsEnabled)
    }
    public func manualInitRegions(
        regions: [RegionConfig],
        handleLoginWithSocialLogin: Bool = true,
        handleLoginWithSSO:Bool = false,
        handleLoginWithCustomSSO:Bool = false,
        entitlementsEnabled: Bool = false
    ) {
        self.regionData = regions
        self.handleLoginWithSocialLogin = handleLoginWithSocialLogin
        self.handleLoginWithSSO = handleLoginWithSSO
        self.handleLoginWithCustomSSO = handleLoginWithCustomSSO
        self.entitlementsEnabled = entitlementsEnabled
        self.auth.manualInitRegions(regions: regions, entitlementsEnabled: entitlementsEnabled)
        self.baseUrl = self.auth.baseUrl
        self.clientId = self.auth.clientId
        self.applicationId = self.auth.applicationId

        SentryHelper.setBaseUrl(self.baseUrl)
        SentryHelper.setClientId(self.clientId)
    }

    public func initWithRegion(regionKey: String){
        
        if self.regionData.count == 0 {
            fatalError(FronteggError.configError(.missingRegions).localizedDescription)
        }
        
        guard let config = self.regionData.first(where: { config in
            config.key == regionKey
        }) else {
            let keys: String = self.regionData.map { config in
                config.key
            }.joined(separator: ", ")
            fatalError(FronteggError.configError(.invalidRegionKey(regionKey, keys)).localizedDescription)
        }
        
        CredentialManager.saveSelectedRegion(regionKey)
        
        self.baseUrl = config.baseUrl
        self.clientId = config.clientId
        self.applicationId = config.applicationId
        self.auth.reinitWithRegion(config: config, entitlementsEnabled: self.entitlementsEnabled)

        SentryHelper.setBaseUrl(self.baseUrl)
        SentryHelper.setClientId(self.clientId)

        logger.info("Frontegg Initialized succcessfully (region: \(regionKey))")
    }
    
    private static func clearKeychain(config: FronteggPlist) -> Bool {
        if config.keepUserLoggedInAfterReinstall {
            return false
        }
        
        let userDefaults = UserDefaults.standard
        if !userDefaults.bool(forKey: "IsFronteggFirstApplicationRun") {
            userDefaults.set(true, forKey: "IsFronteggFirstApplicationRun")
            return true
        }
        return false
    }
}
