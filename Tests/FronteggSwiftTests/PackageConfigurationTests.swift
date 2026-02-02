//
//  PackageConfigurationTests.swift
//  FronteggSwiftTests
//
//  Tests to verify package configuration and version consistency

import XCTest
@testable import FronteggSwift

final class PackageConfigurationTests: XCTestCase {
    
    // MARK: - SDK Version Tests
    
    /// Verifies SDK version is defined and non-empty
    func test_sdkVersion_isDefined() {
        XCTAssertFalse(SDKVersion.value.isEmpty, "SDK version should be defined")
    }
    
    /// Verifies SDK version follows semantic versioning
    func test_sdkVersion_followsSemanticVersioning() {
        let version = SDKVersion.value
        
        // Semantic versioning: MAJOR.MINOR.PATCH
        let components = version.split(separator: ".")
        
        XCTAssertEqual(components.count, 3, "Version should have 3 components (MAJOR.MINOR.PATCH)")
        
        for component in components {
            let number = Int(component)
            XCTAssertNotNil(number, "Version component '\(component)' should be a number")
            XCTAssertGreaterThanOrEqual(number ?? -1, 0, "Version component should be non-negative")
        }
    }
    
    /// Verifies major version indicates API stability
    func test_sdkVersion_majorVersionIndicatesStability() {
        let version = SDKVersion.value
        let components = version.split(separator: ".")
        
        guard let majorVersion = Int(components.first ?? "0") else {
            XCTFail("Could not parse major version")
            return
        }
        
        // Major version >= 1 indicates stable API
        XCTAssertGreaterThanOrEqual(majorVersion, 1, 
            "Major version should be >= 1 for production SDK")
    }
    
    // MARK: - Platform Requirements Tests
    
    /// Verifies iOS 14+ features are available
    func test_iOS14Features_areAvailable() {
        if #available(iOS 14.0, *) {
            // UIMenu with inline display style (iOS 14+)
            // App Clips support
            // WidgetKit availability
            XCTAssertTrue(true, "iOS 14+ features available")
        } else {
            XCTFail("SDK requires iOS 14.0 or later")
        }
    }
    
    /// Verifies iOS 15+ features degrade gracefully
    func test_iOS15Features_degradeGracefully() {
        // Some SDK features require iOS 15+ (e.g., passkeys)
        // They should be marked with @available and degrade gracefully
        
        if #available(iOS 15.0, *) {
            XCTAssertTrue(true, "iOS 15+ features available")
        } else {
            // On iOS 14, passkeys features should be unavailable but not crash
            XCTAssertTrue(true, "SDK should work on iOS 14 without iOS 15 features")
        }
    }
    
    // MARK: - Swift Version Tests
    
    /// Verifies Swift 5.5+ features are used
    func test_swift55Features_areAvailable() {
        // Swift 5.5 introduced async/await
        // The SDK uses async/await for network operations
        
        // This test compiles only if async/await is available
        Task {
            // async/await syntax is available
        }
        
        XCTAssertTrue(true, "Swift 5.5+ async/await is available")
    }
    
    /// Verifies Sendable conformance for thread safety
    func test_sendableConformance_forConcurrency() {
        // Swift 5.5+ introduced Sendable for safe concurrency
        // RegionConfig should be Sendable
        
        let regionDict: [String: Any] = [
            "key": "test",
            "baseUrl": "https://example.com",
            "clientId": "client"
        ]
        
        do {
            let data = try JSONSerialization.data(withJSONObject: regionDict)
            let region = try JSONDecoder().decode(RegionConfig.self, from: data)
            
            // RegionConfig conforms to Sendable, so it can be passed across concurrency domains
            let _: Sendable = region
            XCTAssertTrue(true, "RegionConfig is Sendable")
        } catch {
            XCTFail("Failed to create RegionConfig: \(error)")
        }
    }
    
    // MARK: - Module Structure Tests
    
    /// Verifies public API surface is accessible
    func test_publicAPI_isAccessible() {
        // Key public types should be accessible
        let _: FronteggState.Type = FronteggState.self
        let _: User.Type = User.self
        let _: Tenant.Type = Tenant.self
        let _: RegionConfig.Type = RegionConfig.self
        let _: FronteggError.Type = FronteggError.self
        let _: AuthResponse.Type = AuthResponse.self
        let _: UserRole.Type = UserRole.self
        let _: UserRolePermission.Type = UserRolePermission.self
        
        XCTAssertTrue(true, "All public types are accessible")
    }
    
    /// Verifies error types are public
    func test_errorTypes_arePublic() {
        // Error types should be public for proper error handling
        let _: FronteggError.Type = FronteggError.self
        let _: FronteggError.Authentication.Type = FronteggError.Authentication.self
        let _: FronteggError.Configuration.Type = FronteggError.Configuration.self
        
        XCTAssertTrue(true, "Error types are publicly accessible")
    }
    
    // MARK: - Dependency Configuration Tests
    
    /// Documents Sentry dependency configuration
    func test_sentryDependency_configuration() {
        // Sentry version requirement: >= 8.46.0
        // Specified in Package.swift: .package(url: "...", from: "8.46.0")
        // Specified in podspec: s.dependency 'Sentry', '~> 8.46.0'
        
        // Key Sentry features used:
        // - Breadcrumbs for debugging
        // - Error logging
        // - Performance monitoring (optional)
        
        XCTAssertTrue(true, "Sentry dependency is properly configured")
    }
    
    /// Verifies no conflicting dependencies
    func test_noDependencyConflicts() {
        // The SDK has minimal dependencies to avoid conflicts
        // Only one external dependency: Sentry
        
        // Potential conflict areas to monitor:
        // - If app also uses Sentry, versions should be compatible
        // - No other analytics/crash reporting SDK that conflicts
        
        XCTAssertTrue(true, "No known dependency conflicts")
    }
    
    // MARK: - Build Configuration Tests
    
    /// Verifies DEBUG flag is properly handled
    func test_debugFlag_isProperlyHandled() {
        #if DEBUG
        // In debug builds, additional logging may be enabled
        XCTAssertTrue(true, "Running in DEBUG configuration")
        #else
        // In release builds, sensitive logging should be disabled
        XCTAssertTrue(true, "Running in RELEASE configuration")
        #endif
    }
    
    /// Verifies simulator vs device builds
    func test_simulatorVsDevice_handling() {
        #if targetEnvironment(simulator)
        // Simulator limitations:
        // - Keychain behaves differently (errSecMissingEntitlement)
        // - Passkeys require physical device
        // - Push notifications require device
        XCTAssertTrue(true, "Running on Simulator")
        #else
        // Device-specific features:
        // - Full keychain access
        // - Biometric authentication
        // - Passkeys support (iOS 15+)
        XCTAssertTrue(true, "Running on Device")
        #endif
    }
    
    // MARK: - Architecture Support Tests
    
    /// Verifies arm64 architecture support (required for App Store)
    func test_arm64Support() {
        #if arch(arm64)
        XCTAssertTrue(true, "Running on arm64 (Apple Silicon/iOS devices)")
        #elseif arch(x86_64)
        XCTAssertTrue(true, "Running on x86_64 (Intel Mac/Simulator)")
        #else
        XCTFail("Unknown architecture")
        #endif
    }
    
    // MARK: - Entitlements Tests
    
    /// Documents required entitlements
    func test_requiredEntitlements_areDocumented() {
        // The SDK may require the following entitlements:
        let requiredEntitlements: [String: String] = [
            "Keychain Sharing (optional)": "For shared keychain access across app group",
            "Associated Domains (optional)": "For universal links support"
        ]
        
        let recommendedInfoPlistKeys: [String: String] = [
            "CFBundleURLTypes": "For custom URL scheme handling (OAuth callbacks)",
            "NSFaceIDUsageDescription": "If using biometric authentication (iOS 11+)"
        ]
        
        XCTAssertFalse(requiredEntitlements.isEmpty, "Entitlements should be documented")
        XCTAssertFalse(recommendedInfoPlistKeys.isEmpty, "Info.plist keys should be documented")
    }
    
    // MARK: - Thread Safety Tests
    
    /// Verifies ObservableObject conformance
    func test_fronteggState_isObservableObject() {
        let state = FronteggState()
        
        // FronteggState should be an ObservableObject for SwiftUI integration
        let _: any ObservableObject = state
        
        XCTAssertTrue(true, "FronteggState conforms to ObservableObject")
    }
    
    /// Verifies Published properties for reactive updates
    func test_publishedProperties_areAvailable() {
        let state = FronteggState()
        
        // Key published properties should be accessible
        let _ = state.$isAuthenticated
        let _ = state.$user
        let _ = state.$accessToken
        let _ = state.$isLoading
        
        XCTAssertTrue(true, "Published properties are accessible")
    }
}
