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
    private static var didLogInitStatus = false
    private static let configuredDSN = "https://7f13156fe85003ccf1b968a476787bb1@o362363.ingest.us.sentry.io/4510708685471744"
    private static let sdkName = "FronteggSwift"
    // Thread-safe initialization queue (serial to ensure atomic initialization)
    private static let initQueue = DispatchQueue(label: "com.frontegg.sentry.init")
    private static var sentryEnabledByFeatureFlag: Bool? = nil
    private static let ignoredHTTPStatusCodes: Set<Int> = [502, 503]

    /// Keys whose values must never leave the device in Sentry payloads (headers, tokens, signing material).
    /// Substrings are matched against lowercased keys (covers camelCase JSON and arbitrary `additionalHeaders` keys).
    /// Aligned with `FeLogger` redaction patterns and with HTTP/auth fields used in `Api`, OAuth, and WebAuthn flows.
    private static func breadcrumbKeyIsSensitive(_ key: String) -> Bool {
        let k = key.lowercased()
        if k == "code" || k == "state" { return true }
        if k.hasPrefix("x-amz-") { return true }
        let needles = [
            // Generic / headers (`Api` Authorization, Cookie; passkeys `authorization`)
            "password", "passwd", "secret", "token", "authorization",
            "credential", "signature", "cookie", "set-cookie", "apikey", "api_key",
            "access_key", "bearer",
            // OAuth & refresh bodies (`Api` grant_type flows, token exchange) + FeLogger token keys
            "refresh_token", "id_token", "client_secret", "access_token", "device_token",
            "code_verifier", "verifier",
            // WebAuthn (`Passkeys.swift` challenge; `WebauthnAssertion` clientDataJSON / authenticatorData / signature)
            "challenge", "authenticator", "clientdata", "userhandle",
            // Other secrets sometimes present in auth JSON or callbacks
            "nonce", "jwt", "mfa_token",
        ]
        return needles.contains { k.contains($0) }
    }

    /// Breadcrumb `data` keys whose string values are treated as URLs: query and fragment are stripped.
    private static func breadcrumbKeyHoldsURL(_ key: String) -> Bool {
        let k = key.lowercased()
        if k == "url" || k == "href" || k == "location" { return true }
        return k.hasSuffix("url") || k.hasSuffix("_uri") || k.hasSuffix("uri")
    }

    private static func redactURLQueryAndFragment(_ raw: String) -> String {
        guard let url = URL(string: raw), let host = url.host else {
            return raw.contains("://") && (raw.contains("?") || raw.contains("#")) ? "[redacted_url]" : raw
        }
        let path = url.path.isEmpty ? "/" : url.path
        let scheme = url.scheme ?? "https"
        if let port = url.port {
            return "\(scheme)://\(host):\(port)\(path)"
        }
        return "\(scheme)://\(host)\(path)"
    }

    /// Recursively redacts sensitive keys and URL queries from breadcrumb `data` (SDK + app).
    private static func sanitizeBreadcrumbData(_ data: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        out.reserveCapacity(data.count)
        for (key, value) in data {
            if breadcrumbKeyIsSensitive(key) {
                out[key] = "[redacted]"
                continue
            }
            if breadcrumbKeyHoldsURL(key), let s = value as? String {
                out[key] = redactURLQueryAndFragment(s)
                continue
            }
            if key.lowercased() == "http.query" || key.lowercased() == "http.fragment" {
                out[key] = "[redacted]"
                continue
            }
            switch value {
            case let nested as [String: Any]:
                out[key] = sanitizeBreadcrumbData(nested)
            case let arr as [Any]:
                out[key] = arr.map { element -> Any in
                    if let d = element as? [String: Any] {
                        return sanitizeBreadcrumbData(d)
                    }
                    return element
                }
            default:
                out[key] = value
            }
        }
        return out
    }

    private static func applyBreadcrumbSanitization(_ crumb: Breadcrumb) -> Breadcrumb {
        if let raw = crumb.data {
            var dict: [String: Any] = [:]
            for (k, v) in raw {
                dict[k] = v
            }
            crumb.data = sanitizeBreadcrumbData(dict)
        }
        if let msg = crumb.message, msg.contains("://"), (msg.contains("?") || msg.contains("#")) {
            crumb.message = redactURLQueryAndFragment(msg)
        }
        return crumb
    }

    public static func setSentryEnabledFromFeatureFlag(_ enabled: Bool) {
        initQueue.sync {
            sentryEnabledByFeatureFlag = enabled
        }
    }

    internal static func sentryEnabledByFeatureFlagForTesting() -> Bool? {
        initQueue.sync {
            sentryEnabledByFeatureFlag
        }
    }

    internal static func shouldDropErrorForTesting(_ error: Error, context: [String: [String: Any]] = [:]) -> Bool {
        shouldDropError(error, context: context)
    }

    private static func isSentryEnabled() -> Bool {
        return initQueue.sync {
            guard isInitialized else { return false }
            guard sentryEnabledByFeatureFlag == true else { return false }
            return true
        }
    }

    private static func shouldDropError(_ error: Error, context: [String: [String: Any]]) -> Bool {
        if let apiError = error as? ApiError {
            switch apiError {
            case .meEndpointFailed(let statusCode, _),
                 .refreshEndpointTransient(let statusCode, _):
                return ignoredHTTPStatusCodes.contains(statusCode)
            default:
                break
            }
        }

        if let statusCode = context["http"]?["statusCode"] as? Int {
            return ignoredHTTPStatusCodes.contains(statusCode)
        }

        return false
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


    public static func setBaseUrl(_ baseUrl: String) {
        guard isSentryEnabled() else { return }
        SentrySDK.configureScope { scope in
            scope.setTag(value: baseUrl, key: "baseUrl")
            scope.setContext(value: ["baseUrl": baseUrl], key: "frontegg")
        }
    }

    public static func setClientId(_ clientId: String) {
        guard isSentryEnabled() else { return }
        SentrySDK.configureScope { scope in
            scope.setTag(value: clientId, key: "clientId")
        }
    }

    public static func initialize() {
        initQueue.sync {
            if !didLogInitStatus {
                let config = try? PlistHelper.fronteggConfig()
                logger.info("Sentry SDK initializing (reporting controlled by feature flag mobile-enable-logging, sentryMaxQueueSize=\(config?.sentryMaxQueueSize ?? 30))")
                didLogInitStatus = true
            }

            guard !isInitialized else {
                logger.debug("Sentry already initialized, skipping.")
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

                // Automatic URLSession breadcrumbs include http.query / fragments and can mirror
                // request metadata; we already emit minimal HTTP breadcrumbs from `Api`.
                options.enableNetworkBreadcrumbs = false
                
                // Disable Sentry's automatic network request tracking to avoid:
                // 1. Interfering with our NetworkStatusMonitor offline detection
                // 2. Creating network calls that could trigger false offline detection
                // 3. Consuming bandwidth when our offline mode is active
                // Note: Sentry still handles offline queuing automatically - we're just preventing it from making its own network calls
                options.enableNetworkTracking = false

                options.beforeBreadcrumb = { crumb in
                    Self.applyBreadcrumbSanitization(crumb)
                }
                
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
        if shouldDropError(error, context: context) {
            logger.debug("Dropping Sentry error event for ignored HTTP status (502/503): \(String(reflecting: error))")
            return
        }
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
        _ = applyBreadcrumbSanitization(breadcrumb)
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

    /// Exposed for unit tests (`@testable import`).
    internal static func sanitizeBreadcrumbPayloadForTesting(_ data: [String: Any]) -> [String: Any] {
        sanitizeBreadcrumbData(data)
    }
}
