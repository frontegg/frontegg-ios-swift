//
//  SentryHelper.swift
//
//  Created for Frontegg iOS SDK
//

import Foundation
import Sentry

public class SentryHelper {
    private static let logger = getLogger("SentryHelper")
    private static var isInitialized = false
    private static var isEnabled = false
    private static var didLogInitStatus = false
    private static let configuredDSN = "https://7f13156fe85003ccf1b968a476787bb1@o362363.ingest.us.sentry.io/4510708685471744"
    private static let sdkName = "FronteggSwift"
    // Thread-safe initialization queue (serial to ensure atomic initialization)
    private static let initQueue = DispatchQueue(label: "com.frontegg.sentry.init")
    
    /// Checks if Sentry logging is enabled in the configuration
    private static func isSentryEnabled() -> Bool {
        return initQueue.sync {
            return isEnabled && isInitialized
        }
    }

    private static func parseAssociatedDomains(_ values: [String]) -> [[String: Any]] {
        values.map { raw in
            // Typical values: "applinks:example.com", "webcredentials:example.com"
            if let idx = raw.firstIndex(of: ":") {
                let type = String(raw[..<idx])
                let domain = String(raw[raw.index(after: idx)...])
                return [
                    "type": type,
                    "domain": domain
                ]
            }
            return [
                "type": "unknown",
                "domain": raw
            ]
        }
    }

    private static func payloadContext(_ payload: FronteggPlist.Payload) -> [String: Any] {
        switch payload {
        case .singleRegion(let config):
            return [
                "type": "singleRegion",
                "baseUrl": config.baseUrl,
                "clientId": config.clientId,
                "applicationId": config.applicationId ?? "nil"
            ]
        case .multiRegion(let config):
            return [
                "type": "multiRegion",
                "regions": config.regions.map { region in
                    [
                        "key": region.key,
                        "baseUrl": region.baseUrl,
                        "clientId": region.clientId,
                        "applicationId": region.applicationId ?? "nil"
                    ]
                }
            ]
        }
    }
    
    private static func configureGlobalMetadata() {
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"

        SentrySDK.configureScope { scope in
            scope.setTag(value: sdkName, key: "sdk.name")
            scope.setTag(value: SDKVersion.value, key: "sdk.version")
            scope.setTag(value: "ios", key: "platform")
            scope.setTag(value: bundleId, key: "bundle_id")

            scope.setContext(value: [
                "name": sdkName,
                "version": SDKVersion.value
            ], key: "sdk")

            scope.setContext(value: [
                "bundle_id": bundleId
            ], key: "app")

            if let associatedDomains = getAssociatedDomainsEntitlementInternal() {
                scope.setTag(value: String(associatedDomains.count), key: "associated_domains_count")
                scope.setContext(value: [
                    // Some Sentry projects scrub URL-like strings (e.g., "applinks:...") into [Filtered].
                    // Keep a parsed representation so the domain/type remain visible even with strict scrubbing.
                    "items": parseAssociatedDomains(associatedDomains)
                ], key: "associated_domains")
            }

            if let config = try? PlistHelper.fronteggConfig() {
                // Tags (easy filtering)
                scope.setTag(value: config.keychainService, key: "keychainService")
                scope.setTag(value: String(config.embeddedMode), key: "embeddedMode")
                scope.setTag(value: String(config.loginWithSocialLogin), key: "loginWithSocialLogin")
                scope.setTag(value: String(config.handleLoginWithCustomSocialLoginProvider), key: "handleLoginWithCustomSocialLoginProvider")
                scope.setTag(value: String(config.handleLoginWithSocialProvider), key: "handleLoginWithSocialProvider")
                scope.setTag(value: String(config.loginWithSSO), key: "loginWithSSO")
                scope.setTag(value: String(config.loginWithCustomSSO), key: "loginWithCustomSSO")
                scope.setTag(value: String(config.lateInit), key: "lateInit")
                scope.setTag(value: String(config.keepUserLoggedInAfterReinstall), key: "keepUserLoggedInAfterReinstall")
                scope.setTag(value: String(config.useAsWebAuthenticationForAppleLogin), key: "useAsWebAuthenticationForAppleLogin")
                scope.setTag(value: String(config.shouldSuggestSavePassword), key: "shouldSuggestSavePassword")
                scope.setTag(value: String(config.deleteCookieForHostOnly), key: "deleteCookieForHostOnly")
                scope.setTag(value: String(config.enableOfflineMode), key: "enableOfflineMode")
                scope.setTag(value: String(config.useLegacySocialLoginFlow), key: "useLegacySocialLoginFlow")
                scope.setTag(value: String(config.enableSessionPerTenant), key: "enableSessionPerTenant")
                scope.setTag(value: String(config.enableSentryLogging), key: "enableSentryLogging")
                scope.setTag(value: String(config.sentryMaxQueueSize), key: "sentryMaxQueueSize")
                scope.setTag(value: config.logLevel.rawValue, key: "logLevel")
                scope.setTag(value: String(config.networkMonitoringInterval), key: "networkMonitoringInterval")
                if let backgroundColor = config.backgroundColor {
                    scope.setTag(value: backgroundColor, key: "backgroundColor")
                }
                if let cookieRegex = config.cookieRegex {
                    scope.setTag(value: cookieRegex, key: "cookieRegex")
                }

                scope.setContext(value: [
                    "keychainService": config.keychainService,
                    "embeddedMode": config.embeddedMode,
                    "loginWithSocialLogin": config.loginWithSocialLogin,
                    "handleLoginWithCustomSocialLoginProvider": config.handleLoginWithCustomSocialLoginProvider,
                    "handleLoginWithSocialProvider": config.handleLoginWithSocialProvider,
                    "loginWithSSO": config.loginWithSSO,
                    "loginWithCustomSSO": config.loginWithCustomSSO,
                    "lateInit": config.lateInit,
                    "enableOfflineMode": config.enableOfflineMode,
                    "useLegacySocialLoginFlow": config.useLegacySocialLoginFlow,
                    "enableSessionPerTenant": config.enableSessionPerTenant,
                    "enableSentryLogging": config.enableSentryLogging,
                    "sentryMaxQueueSize": config.sentryMaxQueueSize,
                    "networkMonitoringInterval": config.networkMonitoringInterval,
                    "logLevel": config.logLevel.rawValue,
                    "keepUserLoggedInAfterReinstall": config.keepUserLoggedInAfterReinstall,
                    "useAsWebAuthenticationForAppleLogin": config.useAsWebAuthenticationForAppleLogin,
                    "shouldSuggestSavePassword": config.shouldSuggestSavePassword,
                    "backgroundColor": config.backgroundColor ?? "nil",
                    "cookieRegex": config.cookieRegex ?? "nil",
                    "deleteCookieForHostOnly": config.deleteCookieForHostOnly,
                    "payload": payloadContext(config.payload)
                ], key: "frontegg_config")
            }
        }
    }

    private static func getAssociatedDomainsEntitlementInternal() -> [String]? {
        // Note: Reading entitlements at runtime requires private Security framework APIs
        // which are not allowed by App Store. This function returns nil to avoid using
        // private APIs like _SecTaskCopyValueForEntitlement and _SecTaskCreateFromSelf.
        // The associated domains configuration is still validated at build time by Xcode.
        return nil
    }
    
    // Public method to check associated domains (for logging)
    public static func getAssociatedDomainsEntitlement() -> [String]? {
        return getAssociatedDomainsEntitlementInternal()
    }

    public static func setBaseUrl(_ baseUrl: String) {
        guard isSentryEnabled() else { return }
        SentrySDK.configureScope { scope in
            scope.setTag(value: baseUrl, key: "baseUrl")
            scope.setContext(value: ["baseUrl": baseUrl], key: "frontegg")
        }
    }
    
    public static func initialize() {
        // Use synchronous queue to ensure thread-safe initialization and completion
        initQueue.sync {
            // Log once per app run to make it easy to see if Sentry is enabled.
            if !didLogInitStatus {
                let config = try? PlistHelper.fronteggConfig()
                logger.info("Sentry logging is \(config?.enableSentryLogging == true ? "ENABLED" : "DISABLED") (enableSentryLogging=\(config?.enableSentryLogging ?? false), sentryMaxQueueSize=\(config?.sentryMaxQueueSize ?? 30))")
                didLogInitStatus = true
            }

            // Check if already initialized
            guard !isInitialized else {
                logger.debug("Sentry already initialized, skipping.")
                return
            }
            
            // Check if Sentry logging is enabled in config
            let config = try? PlistHelper.fronteggConfig()
            let enabled = config?.enableSentryLogging ?? false
            
            guard enabled else {
                // Sentry logging is disabled, don't initialize
                logger.info("Sentry initialization skipped (enableSentryLogging=false).")
                return
            }

            // Initialize Sentry SDK (synchronous call)
            SentrySDK.start { options in
                options.dsn = configuredDSN
                options.debug = false
                // Attach a stacktrace to captured messages / errors where possible,
                // so we can see where in the SDK the event originated.
                options.attachStacktrace = true
                options.enableAutoSessionTracking = true
                options.tracesSampleRate = 1.0
                options.sessionTrackingIntervalMillis = 30000
                
                // Sentry SDK has built-in offline support - it automatically queues events when offline
                // and sends them when back online. We just configure it to work well with our offline mode:
                let config = try? PlistHelper.fronteggConfig()
                let maxCacheItems = UInt(config?.sentryMaxQueueSize ?? 30)
                options.maxCacheItems = maxCacheItems // Configurable cache limit to prevent memory abuse during extended offline periods
                options.enableAutoBreadcrumbTracking = true
                
                // Disable Sentry's automatic network request tracking to avoid:
                // 1. Interfering with our NetworkStatusMonitor offline detection
                // 2. Creating network calls that could trigger false offline detection
                // 3. Consuming bandwidth when our offline mode is active
                // Note: Sentry still handles offline queuing automatically - we're just preventing it from making its own network calls
                options.enableNetworkTracking = false
                
                if let bundleId = Bundle.main.bundleIdentifier {
                    options.environment = bundleId
                }
                
                var releaseName = "frontegg-ios-sdk"
                if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                   let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                    releaseName = "\(Bundle.main.bundleIdentifier ?? "frontegg-ios")@\(appVersion)+\(appBuild)"
                }
                releaseName += " (SDK: \(SDKVersion.value))"
                
                options.releaseName = releaseName
            }

            // Set both flags atomically after SentrySDK.start completes
            // This ensures isSentryEnabled() will return true immediately
            // and prevents race conditions where isEnabled=true but isInitialized=false
            isEnabled = true
            isInitialized = true
            logger.info("Sentry initialized successfully.")
        }
        
        // Configure global metadata (can be async since initialization is complete)
        configureGlobalMetadata()
    }
    
    /// Logs an error to Sentry
    /// Note: Sentry SDK automatically queues events when offline and sends them when back online.
    /// The maxQueueSize limit (30) prevents memory abuse during extended offline periods.
    public static func logError(_ error: Error, context: [String: [String: Any]] = [:]) {
        guard isSentryEnabled() else { return }
        SentrySDK.capture(error: error) { scope in
            for (key, value) in context {
                scope.setContext(value: value, key: key)
            }
        }
    }
    
    /// Logs a message to Sentry
    /// Note: Sentry SDK automatically queues events when offline and sends them when back online.
    /// The maxQueueSize limit (30) prevents memory abuse during extended offline periods.
    public static func logMessage(_ message: String, level: SentryLevel = .error, context: [String: [String: Any]] = [:]) {
        guard isSentryEnabled() else { return }
        SentrySDK.capture(message: message) { scope in
            scope.setLevel(level)
            for (key, value) in context {
                scope.setContext(value: value, key: key)
            }
        }
    }
    
    /// Adds a breadcrumb to Sentry
    /// Note: Sentry SDK automatically queues breadcrumbs when offline and sends them when back online.
    /// The maxQueueSize limit (30) prevents memory abuse during extended offline periods.
    public static func addBreadcrumb(_ message: String, category: String = "default", level: SentryLevel = .info, data: [String: Any] = [:]) {
        guard isSentryEnabled() else { return }
        let breadcrumb = Breadcrumb(level: level, category: category)
        breadcrumb.message = message
        breadcrumb.data = data
        SentrySDK.addBreadcrumb(breadcrumb)
    }
    
    public static func setUser(_ userId: String?, email: String? = nil, username: String? = nil) {
        guard isSentryEnabled() else { return }
        let user = Sentry.User()
        user.userId = userId
        user.email = email
        user.username = username
        SentrySDK.setUser(user)
    }
    
    public static func clearUser() {
        guard isSentryEnabled() else { return }
        SentrySDK.setUser(nil)
    }
    
    public static func setTag(_ key: String, value: String) {
        guard isSentryEnabled() else { return }
        SentrySDK.configureScope { scope in
            scope.setTag(value: value, key: key)
        }
    }
    
    public static func setContext(_ key: String, value: [String: Any]) {
        guard isSentryEnabled() else { return }
        SentrySDK.configureScope { scope in
            scope.setContext(value: value, key: key)
        }
    }
}
