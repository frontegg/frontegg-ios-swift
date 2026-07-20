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
    // Isolated Sentry hub/client. The SDK must NEVER call the global `SentrySDK.start()`
    // — doing so binds the global client to Frontegg's DSN and hijacks a host app that
    // runs its own Sentry. All Frontegg telemetry goes through this private hub instead
    // (Sentry's recommended pattern for embedded SDKs). See FR-25990.
    private static var hub: SentryHub?

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

    /// Resets the helper's initialization state so a test can exercise `initialize()`
    /// from a clean slate. Does not (and cannot) stop any already-started global
    /// Sentry client — the whole point of the isolated hub is that we never start one.
    internal static func resetForTesting() {
        initQueue.sync {
            isInitialized = false
            didLogInitStatus = false
            hub = nil
            sentryEnabledByFeatureFlag = nil
        }
    }

    internal static func shouldDropErrorForTesting(_ error: Error, context: [String: [String: Any]] = [:]) -> Bool {
        shouldDropError(error, context: context)
    }

    private static func isSentryEnabled() -> Bool {
        return initQueue.sync {
            guard isInitialized, hub != nil else { return false }
            guard sentryEnabledByFeatureFlag == true else { return false }
            return true
        }
    }

    /// The isolated hub, read under the init lock.
    private static func currentHub() -> SentryHub? {
        initQueue.sync { hub }
    }

    /// Maps Sentry's severity to the SDK's `FeLogger.Level` so breadcrumbs can be
    /// gated against the configured `logLevel` (plist key `logLevel`). Without this
    /// gate, breadcrumbs ship to Sentry on every `info`/`debug` call even when the
    /// host app set `logLevel: warn` to silence verbose logs — which is the actual
    /// driver of our Sentry volume problem.
    private static func mapSentryLevel(_ level: SentryLevel) -> FeLogger.Level? {
        switch level {
        case .debug:   return .debug
        case .info:    return .info
        case .warning: return .warning
        case .error:   return .error
        case .fatal:   return .critical
        case .none:    return nil
        @unknown default: return .info
        }
    }

    /// Returns `true` if a breadcrumb at `level` should be emitted given the
    /// configured `logLevel`. `nil` mapped level → always drop (Sentry `.none`).
    private static func breadcrumbMeetsLogLevelThreshold(_ level: SentryLevel) -> Bool {
        guard let mapped = mapSentryLevel(level) else { return false }
        // FeLogger gate: emit when configured threshold <= message level.
        return PlistHelper.getLogLevel().rawValue <= mapped.rawValue
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
        guard let hub = currentHub() else { return }
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"

        hub.configureScope { scope in
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
        guard isSentryEnabled(), let hub = currentHub() else { return }
        hub.configureScope { scope in
            scope.setTag(value: baseUrl, key: "baseUrl")
            scope.setContext(value: ["baseUrl": baseUrl], key: "frontegg")
        }
    }

    public static func setClientId(_ clientId: String) {
        guard isSentryEnabled(), let hub = currentHub() else { return }
        hub.configureScope { scope in
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

            // Build an ISOLATED Sentry client + hub. We deliberately do NOT call
            // `SentrySDK.start()`: that binds the process-global Sentry client to
            // Frontegg's DSN and hijacks a host app running its own Sentry (FR-25990).
            // A private hub sends only the events we explicitly capture, to our DSN,
            // and leaves the host app's global Sentry untouched.
            let options = Options()
            options.dsn = configuredDSN
            options.debug = false
            // Attach a stacktrace to captured messages / errors where possible,
            // so we can see where in the SDK the event originated.
            options.attachStacktrace = true
            options.tracesSampleRate = 1.0

            // Sentry's client transport has built-in offline support - it queues events
            // when offline and sends them when back online. Bound the cache to avoid
            // memory abuse during extended offline periods.
            let config = try? PlistHelper.fronteggConfig()
            options.maxCacheItems = UInt(config?.sentryMaxQueueSize ?? 30)

            // Redact breadcrumb data/URLs at the client boundary too (belt-and-suspenders
            // alongside the manual sanitization in `addBreadcrumb`).
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

            guard let client = SentryClient(options: options) else {
                logger.error("Failed to create isolated Sentry client; Frontegg telemetry disabled.")
                return
            }
            hub = SentryHub(client: client, andScope: Scope())

            isInitialized = true
            logger.info("Sentry initialized successfully (isolated hub).")
        }
        
        // Configure global metadata (can be async since initialization is complete)
        configureGlobalMetadata()
    }
    
    /// Logs an error to Sentry
    /// Note: Sentry SDK automatically queues events when offline and sends them when back online.
    /// The maxQueueSize limit (30) prevents memory abuse during extended offline periods.
    public static func logError(_ error: Error, context: [String: [String: Any]] = [:]) {
        guard isSentryEnabled(), let hub = currentHub() else { return }
        if shouldDropError(error, context: context) {
            logger.debug("Dropping Sentry error event for ignored HTTP status (502/503): \(String(reflecting: error))")
            return
        }
        // Copy the hub's scope (global metadata) and layer the per-call context on top,
        // so the event carries both without mutating the shared hub scope.
        let scope = Scope(scope: hub.scope)
        for (key, value) in context {
            scope.setContext(value: value, key: key)
        }
        hub.capture(error: error, scope: scope)
    }
    
    /// Logs a message to Sentry
    /// Note: Sentry SDK automatically queues events when offline and sends them when back online.
    /// The maxQueueSize limit (30) prevents memory abuse during extended offline periods.
    public static func logMessage(_ message: String, level: SentryLevel = .error, context: [String: [String: Any]] = [:]) {
        guard isSentryEnabled(), let hub = currentHub() else { return }
        let scope = Scope(scope: hub.scope)
        scope.setLevel(level)
        for (key, value) in context {
            scope.setContext(value: value, key: key)
        }
        hub.capture(message: message, scope: scope)
    }
    
    /// Adds a breadcrumb to Sentry.
    ///
    /// Breadcrumbs at a `level` below the configured `logLevel` (plist key
    /// `logLevel`, default `.warning`) are dropped. This keeps the breadcrumb
    /// surface consistent with `os_log` output and prevents the SDK from
    /// shipping verbose `info`/`debug` context to Sentry when the host app has
    /// asked for a quieter SDK.
    ///
    /// Note: Sentry SDK automatically queues breadcrumbs when offline and sends them when back online.
    /// The maxQueueSize limit (30) prevents memory abuse during extended offline periods.
    public static func addBreadcrumb(_ message: String, category: String = "default", level: SentryLevel = .info, data: [String: Any] = [:]) {
        guard isSentryEnabled(), let hub = currentHub() else { return }
        guard breadcrumbMeetsLogLevelThreshold(level) else { return }
        let breadcrumb = Breadcrumb(level: level, category: category)
        breadcrumb.message = message
        breadcrumb.data = data
        _ = applyBreadcrumbSanitization(breadcrumb)
        hub.add(breadcrumb)
    }

    /// Exposed for unit tests (`@testable import`).
    internal static func breadcrumbMeetsLogLevelThresholdForTesting(_ level: SentryLevel) -> Bool {
        breadcrumbMeetsLogLevelThreshold(level)
    }
    
    public static func setUser(_ userId: String?, email: String? = nil, username: String? = nil) {
        guard isSentryEnabled(), let hub = currentHub() else { return }
        let user = Sentry.User()
        user.userId = userId
        user.email = email
        user.username = username
        hub.setUser(user)
    }

    public static func clearUser() {
        guard isSentryEnabled(), let hub = currentHub() else { return }
        hub.setUser(nil)
    }

    public static func setTag(_ key: String, value: String) {
        guard isSentryEnabled(), let hub = currentHub() else { return }
        hub.configureScope { scope in
            scope.setTag(value: value, key: key)
        }
    }

    public static func setContext(_ key: String, value: [String: Any]) {
        guard isSentryEnabled(), let hub = currentHub() else { return }
        hub.configureScope { scope in
            scope.setContext(value: value, key: key)
        }
    }

    /// Exposed for unit tests (`@testable import`).
    internal static func sanitizeBreadcrumbPayloadForTesting(_ data: [String: Any]) -> [String: Any] {
        sanitizeBreadcrumbData(data)
    }
}
