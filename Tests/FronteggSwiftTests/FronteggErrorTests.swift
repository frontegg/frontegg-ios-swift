//
//  FronteggErrorTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

final class FronteggErrorTests: XCTestCase {

    // MARK: - FronteggError.Configuration errorDescription

    func test_configuration_couldNotLoadPlist_description() {
        let error = FronteggError.Configuration.couldNotLoadPlist("file not found")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("Could not load") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("file not found") ?? false)
    }

    func test_configuration_couldNotGetBundleID_description() {
        let error = FronteggError.Configuration.couldNotGetBundleID("/app/path")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("/app/path") ?? false)
    }

    func test_configuration_missingPlist_description() {
        let error = FronteggError.Configuration.missingPlist
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("Missing") ?? false)
    }

    func test_configuration_missingClientIdOrBaseURL_description() {
        let error = FronteggError.Configuration.missingClientIdOrBaseURL("/path/to/plist")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("/path/to/plist") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("clientId") ?? false)
    }

    func test_configuration_missingRegions_description() {
        let error = FronteggError.Configuration.missingRegions
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.lowercased().contains("region") ?? false)
    }

    func test_configuration_invalidRegions_description() {
        let error = FronteggError.Configuration.invalidRegions("/path")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("/path") ?? false)
    }

    func test_configuration_invalidRegionKey_description() {
        let error = FronteggError.Configuration.invalidRegionKey("eu", "us, eu")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("eu") ?? false)
    }

    func test_configuration_failedToGenerateAuthorizeURL_description() {
        let error = FronteggError.Configuration.failedToGenerateAuthorizeURL
        XCTAssertNotNil(error.errorDescription)
    }

    func test_configuration_socialLoginMissing_description() {
        let error = FronteggError.Configuration.socialLoginMissing("Google")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("Google") ?? false)
    }

    func test_configuration_wrongBaseUrl_description() {
        let error = FronteggError.Configuration.wrongBaseUrl("http://bad.com", "must use https")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("http://bad.com") ?? false)
    }

    func test_configError_wrapsConfiguration() {
        let config = FronteggError.Configuration.missingPlist
        let error = FronteggError.configError(config)
        XCTAssertNotNil(error.errorDescription)
    }
}
