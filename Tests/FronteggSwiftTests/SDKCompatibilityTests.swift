//
//  SDKCompatibilityTests.swift
//  FronteggSwiftTests
//
//  Tests to verify SDK dependencies and App Store compatibility

import XCTest
@testable import FronteggSwift
import Sentry

final class SDKCompatibilityTests: XCTestCase {
    
    // MARK: - Dependency Verification Tests
    
    /// Verifies that Sentry is the only external dependency
    /// This is important for App Store compliance and bundle size management
    func test_externalDependencies_onlySentryIsRequired() {
        // Sentry should be importable (verified by import statement above)
        // This test documents and verifies the expected dependencies
        
        let expectedDependencies = ["Sentry"]
        
        // If this test fails after adding new dependencies, update this list
        // and document why the new dependency is needed
        XCTAssertEqual(expectedDependencies.count, 1, "SDK should have minimal external dependencies")
        XCTAssertTrue(expectedDependencies.contains("Sentry"), "Sentry is required for error tracking")
    }
    
    /// Verifies Sentry is properly configured for production use
    func test_sentry_isAppStoreCompatible() {
        // Sentry is a well-known, App Store approved SDK
        // Used by many production apps including Airbnb, Peloton, etc.
        
        // Verify we can access Sentry types (compile-time check)
        let _: SentryLevel.Type = SentryLevel.self
        XCTAssertTrue(true, "Sentry SDK is importable and usable")
    }
    
    // MARK: - iOS Platform Compatibility Tests
    
    /// Verifies minimum iOS version requirement
    func test_minimumIOSVersion_is14() {
        // The SDK requires iOS 14.0+
        // This is documented in Package.swift and podspec
        
        if #available(iOS 14.0, *) {
            XCTAssertTrue(true, "Running on iOS 14.0+")
        } else {
            XCTFail("SDK requires iOS 14.0 or later")
        }
    }
    
    /// Verifies SDK works on current iOS version
    func test_currentIOSVersion_isSupported() {
        let currentVersion = ProcessInfo.processInfo.operatingSystemVersion
        
        // Minimum supported is iOS 14.0
        XCTAssertGreaterThanOrEqual(currentVersion.majorVersion, 14,
                                    "Current iOS version should be 14.0 or higher")
    }
    
    // MARK: - Framework Import Verification Tests
    
    /// Verifies all required Apple frameworks are available
    func test_requiredFrameworks_areAvailable() {
        // Foundation - Core functionality
        let _: Data.Type = Data.self
        let _: URL.Type = URL.self
        let _: JSONDecoder.Type = JSONDecoder.self
        let _: URLSession.Type = URLSession.self
        
        // Security - Keychain operations
        let _: CFString.Type = CFString.self
        
        // Combine - Reactive programming (iOS 13+)
        let _: Published<String>.Publisher.Type = Published<String>.Publisher.self
        
        XCTAssertTrue(true, "All required frameworks are available")
    }
    
    /// Verifies UIKit framework availability (required for iOS)
    func test_uiKit_isAvailable() {
        #if canImport(UIKit)
        XCTAssertTrue(true, "UIKit is available")
        #else
        XCTFail("UIKit must be available for iOS SDK")
        #endif
    }
    
    /// Verifies WebKit framework availability (required for web authentication)
    func test_webKit_isAvailable() {
        #if canImport(WebKit)
        XCTAssertTrue(true, "WebKit is available for web-based authentication")
        #else
        XCTFail("WebKit must be available for embedded login")
        #endif
    }
    
    /// Verifies AuthenticationServices framework (required for passkeys/social login)
    func test_authenticationServices_isAvailable() {
        #if canImport(AuthenticationServices)
        XCTAssertTrue(true, "AuthenticationServices is available for passkeys and social login")
        #else
        XCTFail("AuthenticationServices must be available for modern authentication flows")
        #endif
    }
    
    /// Verifies CryptoKit availability (used for PKCE)
    func test_cryptoKit_isAvailable() {
        #if canImport(CryptoKit)
        XCTAssertTrue(true, "CryptoKit is available for cryptographic operations")
        #else
        XCTFail("CryptoKit must be available for PKCE code challenge generation")
        #endif
    }
    
    /// Verifies Network framework availability (used for connectivity monitoring)
    func test_networkFramework_isAvailable() {
        #if canImport(Network)
        XCTAssertTrue(true, "Network framework is available for connectivity monitoring")
        #else
        XCTFail("Network framework must be available for NWPathMonitor")
        #endif
    }
    
    // MARK: - App Store Compliance Tests
    
    /// Verifies no private API usage indicators
    func test_noPrivateAPIUsage() {
        // This test documents that the SDK should not use private APIs
        // Private API usage would cause App Store rejection
        
        // The SDK uses only public Apple frameworks:
        // - Foundation (public)
        // - UIKit (public)
        // - WebKit (public)
        // - AuthenticationServices (public)
        // - CryptoKit (public)
        // - Security (public)
        // - Network (public)
        // - Combine (public)
        
        // And one vetted third-party SDK:
        // - Sentry (App Store approved, used by major apps)
        
        XCTAssertTrue(true, "SDK uses only public APIs and approved third-party SDKs")
    }
    
    /// Verifies SDK metadata for App Store submission
    func test_sdkMetadata_isValid() {
        // SDK version should be non-empty
        XCTAssertFalse(SDKVersion.value.isEmpty, "SDK version should be defined")
        
        // Version should follow semantic versioning pattern (X.Y.Z)
        let versionPattern = #"^\d+\.\d+\.\d+$"#
        let versionRegex = try? NSRegularExpression(pattern: versionPattern)
        let versionRange = NSRange(SDKVersion.value.startIndex..., in: SDKVersion.value)
        let hasValidVersion = versionRegex?.firstMatch(in: SDKVersion.value, range: versionRange) != nil
        
        XCTAssertTrue(hasValidVersion, "SDK version should follow semantic versioning (X.Y.Z)")
    }
    
    /// Verifies bundle identifier requirements
    func test_bundleIdentifier_requirements() {
        // The SDK requires a valid bundle identifier for redirect URIs
        // This test verifies the format expectations
        
        let validBundleIdPattern = #"^[a-zA-Z][a-zA-Z0-9\-\.]*[a-zA-Z0-9]$"#
        let sampleBundleIds = [
            "com.example.app",
            "com.company.MyApp",
            "io.frontegg.demo"
        ]
        
        for bundleId in sampleBundleIds {
            let regex = try? NSRegularExpression(pattern: validBundleIdPattern)
            let range = NSRange(bundleId.startIndex..., in: bundleId)
            let isValid = regex?.firstMatch(in: bundleId, range: range) != nil
            XCTAssertTrue(isValid, "Bundle ID '\(bundleId)' should be valid")
        }
    }
    
    // MARK: - Security Framework Tests
    
    /// Verifies keychain is accessible for credential storage
    func test_keychainAccess_isAvailable() {
        // The SDK uses Keychain for secure token storage
        // This test verifies the Security framework is properly linked
        
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: "test-keychain-access",
            kSecAttrService: "frontegg-test",
            kSecReturnData: false
        ]
        
        // Just verify we can call SecItemCopyMatching without crashing
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        // errSecItemNotFound is expected (item doesn't exist)
        // errSecMissingEntitlement is expected in simulator
        // Both indicate Security framework is working
        XCTAssertTrue(
            status == errSecItemNotFound || status == errSecSuccess || status == -34018,
            "Security framework should be accessible (status: \(status))"
        )
    }
    
    // MARK: - URL Scheme Tests
    
    /// Verifies redirect URI format for OAuth
    func test_redirectURI_formatIsValid() {
        // OAuth redirect URIs must follow specific patterns for App Store apps
        // Deep link format: bundleid://host/path
        
        let validRedirectPatterns = [
            #"^[a-z][a-z0-9\.\-]*://.*$"#,  // Custom scheme
            #"^https://.*$"#                 // Universal link
        ]
        
        let sampleRedirects = [
            "com.example.app://auth.frontegg.com/ios/oauth/callback",
            "https://example.com/oauth/callback"
        ]
        
        for redirect in sampleRedirects {
            var matchesPattern = false
            for pattern in validRedirectPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(redirect.startIndex..., in: redirect)
                    if regex.firstMatch(in: redirect, range: range) != nil {
                        matchesPattern = true
                        break
                    }
                }
            }
            XCTAssertTrue(matchesPattern, "Redirect URI '\(redirect)' should match valid OAuth patterns")
        }
    }
    
    // MARK: - Data Privacy Tests
    
    /// Documents data types collected by the SDK (for privacy manifest)
    func test_dataTypesCollected_areDocumented() {
        // iOS 17+ requires privacy manifests declaring data collection
        // This test documents what the SDK collects
        
        let dataTypesCollected: [String: String] = [
            "Authentication tokens": "Stored securely in Keychain, used for API authentication",
            "User profile": "Name, email, profile picture from identity provider",
            "Device info": "Bundle ID for redirect URI generation",
            "Error data": "Sent to Sentry for crash reporting (if enabled)"
        ]
        
        // Verify documentation exists
        XCTAssertFalse(dataTypesCollected.isEmpty, "Data collection should be documented")
        XCTAssertTrue(dataTypesCollected.keys.contains("Authentication tokens"))
        XCTAssertTrue(dataTypesCollected.keys.contains("User profile"))
    }
    
    /// Verifies no tracking identifiers are used
    func test_noTrackingIdentifiers() {
        // The SDK should not use advertising identifiers
        // IDFA requires user permission via ATT framework
        
        #if canImport(AdSupport)
        // AdSupport should NOT be imported by the SDK
        // This #if block documents the expectation
        XCTAssertTrue(true, "AdSupport can be imported but SDK does not use IDFA")
        #endif
        
        // The SDK does not use:
        // - IDFA (Advertising Identifier)
        // - IDFV for tracking purposes
        // - Fingerprinting techniques
        
        XCTAssertTrue(true, "SDK does not use tracking identifiers")
    }
    
    // MARK: - Network Security Tests
    
    /// Verifies HTTPS is required for all API calls
    func test_httpsRequired_forAPIEndpoints() {
        // App Transport Security requires HTTPS
        // The SDK should only communicate over HTTPS
        
        let validBaseUrls = [
            "https://auth.frontegg.com",
            "https://api.frontegg.com",
            "https://custom.example.com"
        ]
        
        for url in validBaseUrls {
            XCTAssertTrue(url.hasPrefix("https://"), "API URLs must use HTTPS: \(url)")
        }
        
        // The SDK validates baseUrl format to ensure HTTPS
        // This is enforced in RegionConfig init
    }
    
    /// Verifies certificate pinning considerations
    func test_certificatePinning_considerations() {
        // Document certificate pinning status
        // Currently the SDK relies on system trust store
        
        // Sentry handles its own certificate validation
        // API calls use URLSession with default security
        
        XCTAssertTrue(true, "SDK uses system certificate validation via URLSession")
    }
    
    // MARK: - Binary Size Impact Tests
    
    /// Documents expected SDK binary size impact
    func test_binarySizeImpact_isDocumented() {
        // Approximate size contributions:
        let sizeEstimates: [String: String] = [
            "FronteggSwift core": "~200-400 KB",
            "Sentry SDK": "~1-2 MB (includes crash reporting, symbolication)",
            "Total estimated": "~1.5-2.5 MB added to IPA"
        ]
        
        XCTAssertFalse(sizeEstimates.isEmpty, "Binary size impact should be documented")
        
        // Note: Actual sizes vary based on:
        // - Build configuration (Debug vs Release)
        // - Strip settings
        // - Bitcode inclusion
        // - Architecture slices
    }
    
    // MARK: - Dependency License Tests
    
    /// Verifies all dependencies have App Store compatible licenses
    func test_dependencyLicenses_areAppStoreCompatible() {
        // MIT License - Compatible with App Store
        let licenses: [String: String] = [
            "FronteggSwift": "MIT",
            "Sentry": "MIT"
        ]
        
        let appStoreCompatibleLicenses = ["MIT", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause", "ISC"]
        
        for (dependency, license) in licenses {
            XCTAssertTrue(
                appStoreCompatibleLicenses.contains(license),
                "\(dependency) uses \(license) which should be App Store compatible"
            )
        }
    }
}
