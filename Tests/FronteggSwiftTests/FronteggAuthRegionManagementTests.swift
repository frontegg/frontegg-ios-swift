//
//  FronteggAuthRegionManagementTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

final class FronteggAuthRegionManagementTests: XCTestCase {

    private var auth: FronteggAuth!
    private var credentialManager: CredentialManager!
    private var serviceKey: String!

    private let usRegion = RegionConfig(key: "us", baseUrl: "https://us.frontegg.com", clientId: "us-client-id", applicationId: nil)
    private let euRegion = RegionConfig(key: "eu", baseUrl: "https://eu.frontegg.com", clientId: "eu-client-id", applicationId: nil)
    private let apRegion = RegionConfig(key: "ap", baseUrl: "https://ap.frontegg.com", clientId: "ap-client-id", applicationId: "ap-app-id")

    override func setUp() {
        super.setUp()
        serviceKey = "frontegg-region-test-\(UUID().uuidString)"
        credentialManager = CredentialManager(serviceKey: serviceKey)

        PlistHelper.testConfigOverride = FronteggPlist(
            keychainService: serviceKey,
            lateInit: true,
            payload: .singleRegion(
                .init(baseUrl: "https://placeholder.frontegg.com", clientId: "placeholder")
            ),
            keepUserLoggedInAfterReinstall: false
        )

        auth = FronteggAuth(
            baseUrl: "https://placeholder.frontegg.com",
            clientId: "placeholder",
            applicationId: nil,
            credentialManager: credentialManager,
            isRegional: true,
            regionData: [usRegion, euRegion, apRegion],
            embeddedMode: false,
            isLateInit: true
        )
    }

    override func tearDown() {
        auth?.cancelScheduledTokenRefresh()
        credentialManager?.clear()
        // Clear saved region from UserDefaults
        UserDefaults.standard.removeObject(forKey: KeychainKeys.region.rawValue)
        PlistHelper.testConfigOverride = nil
        auth = nil
        credentialManager = nil
        serviceKey = nil
        super.tearDown()
    }

    // MARK: - manualInit

    func test_manualInit_sets_baseUrl_clientId_applicationId() {
        auth.manualInit(
            baseUrl: "https://custom.frontegg.com",
            clientId: "custom-client",
            applicationId: "custom-app"
        )
        XCTAssertEqual(auth.baseUrl, "https://custom.frontegg.com")
        XCTAssertEqual(auth.clientId, "custom-client")
        XCTAssertEqual(auth.applicationId, "custom-app")
    }

    func test_manualInit_sets_isRegional_false() {
        auth.manualInit(
            baseUrl: "https://single.frontegg.com",
            clientId: "single-client",
            applicationId: nil
        )
        XCTAssertFalse(auth.isRegional)
    }

    func test_manualInit_creates_new_api_instance() {
        let oldApi = auth.api
        auth.manualInit(
            baseUrl: "https://new.frontegg.com",
            clientId: "new-client",
            applicationId: nil
        )
        // Api is a reference type — after manualInit a new instance is created
        XCTAssertFalse(auth.api === oldApi, "manualInit should create a new Api instance")
    }

    // MARK: - manualInitRegions

    func test_manualInitRegions_with_saved_region_selects_it() {
        CredentialManager.saveSelectedRegion("eu")
        auth.manualInitRegions(regions: [usRegion, euRegion, apRegion])

        XCTAssertEqual(auth.baseUrl, "https://eu.frontegg.com")
        XCTAssertEqual(auth.clientId, "eu-client-id")
        XCTAssertEqual(auth.selectedRegion?.key, "eu")
    }

    func test_manualInitRegions_without_saved_region_falls_back_to_first() {
        UserDefaults.standard.removeObject(forKey: KeychainKeys.region.rawValue)
        auth.manualInitRegions(regions: [usRegion, euRegion])

        // Without a saved region, selectedRegion is nil, but fallback uses first region
        XCTAssertEqual(auth.baseUrl, "https://us.frontegg.com")
        XCTAssertEqual(auth.clientId, "us-client-id")
    }

    func test_manualInitRegions_empty_regions_does_not_crash() {
        auth.manualInitRegions(regions: [])
        // Should not crash; baseUrl remains unchanged from init
        XCTAssertTrue(auth.isRegional)
    }

    // MARK: - reinitWithRegion

    func test_reinitWithRegion_updates_baseUrl_and_clientId() {
        auth.reinitWithRegion(config: apRegion)
        XCTAssertEqual(auth.baseUrl, "https://ap.frontegg.com")
        XCTAssertEqual(auth.clientId, "ap-client-id")
        XCTAssertEqual(auth.applicationId, "ap-app-id")
    }

    func test_reinitWithRegion_sets_selected_region_in_memory() {
        auth.reinitWithRegion(config: euRegion)
        XCTAssertEqual(auth.selectedRegion?.key, "eu")
    }

    func test_region_persists_via_credentialManager_saveSelectedRegion() {
        // FronteggApp.initWithRegion saves to UserDefaults via CredentialManager.saveSelectedRegion
        CredentialManager.saveSelectedRegion("eu")
        XCTAssertEqual(CredentialManager.getSelectedRegion(), "eu")
    }

    // MARK: - getSelectedRegion

    func test_getSelectedRegion_returns_nil_when_no_region_saved() {
        UserDefaults.standard.removeObject(forKey: KeychainKeys.region.rawValue)
        XCTAssertNil(auth.getSelectedRegion())
    }

    func test_getSelectedRegion_returns_matching_region() {
        CredentialManager.saveSelectedRegion("ap")
        let region = auth.getSelectedRegion()
        XCTAssertEqual(region?.key, "ap")
        XCTAssertEqual(region?.baseUrl, "https://ap.frontegg.com")
    }

    func test_getSelectedRegion_returns_nil_for_invalid_key() {
        CredentialManager.saveSelectedRegion("nonexistent-region")
        XCTAssertNil(auth.getSelectedRegion())
    }

    func test_region_selection_persists_across_auth_instances() {
        // Simulate FronteggApp persisting the region selection
        CredentialManager.saveSelectedRegion("eu")

        // Create a new auth instance with same regionData
        let auth2 = FronteggAuth(
            baseUrl: "https://placeholder.frontegg.com",
            clientId: "placeholder",
            applicationId: nil,
            credentialManager: credentialManager,
            isRegional: true,
            regionData: [usRegion, euRegion, apRegion],
            embeddedMode: false,
            isLateInit: true
        )

        let selectedRegion = auth2.getSelectedRegion()
        XCTAssertEqual(selectedRegion?.key, "eu")
        auth2.cancelScheduledTokenRefresh()
    }
}
