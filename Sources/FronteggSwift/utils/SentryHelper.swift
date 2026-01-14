//
//  SentryHelper.swift
//
//  Created for Frontegg iOS SDK
//

import Foundation
import Sentry

public class SentryHelper {
    private static var isInitialized = false
    private static let configuredDSN = "https://7f13156fe85003ccf1b968a476787bb1@o362363.ingest.us.sentry.io/4510708685471744"
    private static let sdkName = "FronteggSwift"
    private static let sdkVersion = "1.2.67"
    
    private static func configureGlobalMetadata() {
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"

        SentrySDK.configureScope { scope in
            scope.setTag(value: sdkName, key: "sdk.name")
            scope.setTag(value: sdkVersion, key: "sdk.version")
            scope.setTag(value: "ios", key: "platform")
            scope.setTag(value: bundleId, key: "bundle_id")

            scope.setContext(value: [
                "name": sdkName,
                "version": sdkVersion
            ], key: "sdk")

            scope.setContext(value: [
                "bundle_id": bundleId
            ], key: "app")

            if let config = try? PlistHelper.fronteggConfig() {
                scope.setTag(value: String(config.embeddedMode), key: "embeddedMode")
                scope.setTag(value: String(config.enableOfflineMode), key: "enableOfflineMode")
                scope.setTag(value: String(config.enableSessionPerTenant), key: "enableSessionPerTenant")
                scope.setTag(value: String(config.enableTraceIdLogging), key: "enableTraceIdLogging")
                scope.setTag(value: config.logLevel.rawValue, key: "logLevel")

                scope.setContext(value: [
                    "embeddedMode": config.embeddedMode,
                    "enableOfflineMode": config.enableOfflineMode,
                    "enableSessionPerTenant": config.enableSessionPerTenant,
                    "enableTraceIdLogging": config.enableTraceIdLogging,
                    "networkMonitoringInterval": config.networkMonitoringInterval,
                    "logLevel": config.logLevel.rawValue
                ], key: "frontegg_config")
            }
        }
    }

    public static func setBaseUrl(_ baseUrl: String) {
        guard isInitialized else { return }
        SentrySDK.configureScope { scope in
            scope.setTag(value: baseUrl, key: "baseUrl")
            scope.setContext(value: ["baseUrl": baseUrl], key: "frontegg")
        }
    }
    
    public static func initialize() {
        guard !isInitialized else {
            return
        }

        SentrySDK.start { options in
            options.dsn = configuredDSN
            options.debug = false
            options.enableAutoSessionTracking = true
            options.tracesSampleRate = 1.0
            options.sessionTrackingIntervalMillis = 30000
            
            if let bundleId = Bundle.main.bundleIdentifier {
                options.environment = bundleId
            }
            
            var releaseName = "frontegg-ios-sdk"
            if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
               let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                releaseName = "\(Bundle.main.bundleIdentifier ?? "frontegg-ios")@\(appVersion)+\(appBuild)"
            }
            releaseName += " (SDK: \(sdkVersion))"
            
            options.releaseName = releaseName
        }

        isInitialized = true
        configureGlobalMetadata()
    }
    
    public static func logError(_ error: Error, context: [String: [String: Any]] = [:]) {
        guard isInitialized else { return }
        SentrySDK.capture(error: error) { scope in
            for (key, value) in context {
                scope.setContext(value: value, key: key)
            }
        }
    }
    
    public static func logMessage(_ message: String, level: SentryLevel = .error, context: [String: [String: Any]] = [:]) {
        guard isInitialized else { return }
        SentrySDK.capture(message: message) { scope in
            scope.setLevel(level)
            for (key, value) in context {
                scope.setContext(value: value, key: key)
            }
        }
    }
    
    public static func addBreadcrumb(_ message: String, category: String = "default", level: SentryLevel = .info, data: [String: Any] = [:]) {
        guard isInitialized else { return }
        let breadcrumb = Breadcrumb(level: level, category: category)
        breadcrumb.message = message
        breadcrumb.data = data
        SentrySDK.addBreadcrumb(breadcrumb)
    }
    
    public static func setUser(_ userId: String?, email: String? = nil, username: String? = nil) {
        guard isInitialized else { return }
        let user = Sentry.User()
        user.userId = userId
        user.email = email
        user.username = username
        SentrySDK.setUser(user)
    }
    
    public static func clearUser() {
        guard isInitialized else { return }
        SentrySDK.setUser(nil)
    }
    
    public static func setTag(_ key: String, value: String) {
        guard isInitialized else { return }
        SentrySDK.configureScope { scope in
            scope.setTag(value: value, key: key)
        }
    }
    
    public static func setContext(_ key: String, value: [String: Any]) {
        guard isInitialized else { return }
        SentrySDK.configureScope { scope in
            scope.setContext(value: value, key: key)
        }
    }
}
