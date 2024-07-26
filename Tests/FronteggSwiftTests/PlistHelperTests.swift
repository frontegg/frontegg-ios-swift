//
//  File.swift
//  
//
//  Created by Nick Hagi on 25/07/2024.
//

import XCTest
@testable import FronteggSwift

final class PlistHelperTests: XCTestCase {}

// MARK: - Valid FronteggConfig Tests
extension PlistHelperTests {

    func test_decodePlist_willDecodeSingleRegionCorrectly() throws {

        let expectedPlist = FronteggPlist(
            keychainService: "testService",
            embeddedMode: false,
            loginWithSocialLogin: false,
            loginWithSSO: true,
            lateInit: true,
            payload: .singleRegion(.init(
                baseUrl: "https://test.com",
                clientId: "d37ad699-e466-451a-a9d1-d590869dba1a",
                applicationId: "f87f8fea-8cb3-4a46-bab8-0169726a5704"
            ))
        )
        let decodedPlist = try PlistHelper.decode(
            FronteggPlist.self,
            from: MockRegion.validSingleRegion.data,
            at: "testPath"
        )

        XCTAssertEqual(expectedPlist, decodedPlist)
    }

    func test_decodePlist_willDecodeMultiRegionCorrectly() throws {

        let expectedPlist = FronteggPlist(
            keychainService: "testService",
            embeddedMode: false,
            loginWithSocialLogin: false,
            loginWithSSO: true,
            lateInit: true,
            payload: .multiRegion(.init(regions: [
                .init(
                    key: "region1",
                    baseUrl: "https://region1.test.com",
                    clientId: "f87f8fea-8cb3-4a46-bab8-0169726a5704",
                    applicationId: "549e3240-84e2-495a-91ea-be467f807272"
                ),
                .init(
                    key: "region2",
                    baseUrl: "https://region2.test.com",
                    clientId: "d37ad699-e466-451a-a9d1-d590869dba1a",
                    applicationId: "199d93c3-0d82-4eac-ab95-4b9e3d617053"
                )
            ]))
        )
        let decodedPlist = try PlistHelper.decode(
            FronteggPlist.self,
            from: MockRegion.validMultiRegion.data,
            at: "testPath"
        )

        XCTAssertEqual(expectedPlist, decodedPlist)
    }
}

// MARK: - DecodingError Mapping Tests
extension PlistHelperTests {

    func test_decodeSingleRegion_willThrowCorrectError_whenBaseUrlIsMissing() throws {

        XCTAssertThrowsError(
            try PlistHelper.decode(
                SingleRegionConfig.self,
                from: MockRegion.singleRegionMissingBaseUrl.data,
                at: "testPath"
            )
        ) { error in
            XCTAssertEqual(error as? FronteggError.Configuration, .missingClientIdOrBaseURL("testPath"))
        }
    }

    func test_decodeSingleRegion_willThrowCorrectError_whenClientIdIsMissing() throws {

        XCTAssertThrowsError(
            try PlistHelper.decode(
                SingleRegionConfig.self,
                from: MockRegion.singleRegionMissingClientId.data,
                at: "testPath"
            )
        ) { error in
            XCTAssertEqual(error as? FronteggError.Configuration, .missingClientIdOrBaseURL("testPath"))
        }
    }

    func test_decodeMultiRegion_willThrowCorrectError_whenBaseUrlIsMissing() throws {


        XCTAssertThrowsError(
            try PlistHelper.decode(
                MultiRegionConfig.self,
                from: MockRegion.multiRegionMissingBaseUrl.data,
                at: "testPath"
            )
        ) { error in
            XCTAssertEqual(error as? FronteggError.Configuration, .missingClientIdOrBaseURL("testPath"))
        }
    }

    func test_decodeMultiRegion_willThrowCorrectError_whenClientIdIsMissing() throws {


        XCTAssertThrowsError(
            try PlistHelper.decode(
                MultiRegionConfig.self,
                from: MockRegion.multiRegionMissingClientId.data,
                at: "testPath"
            )
        ) { error in
            XCTAssertEqual(error as? FronteggError.Configuration, .missingClientIdOrBaseURL("testPath"))
        }
    }
}

private struct TestError: Error {}
