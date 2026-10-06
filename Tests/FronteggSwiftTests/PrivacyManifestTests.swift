import XCTest
@testable import FronteggSwift

final class PrivacyManifestTests: XCTestCase {

    private func loadManifest(file: StaticString = #filePath, line: UInt = #line) throws -> [String: Any] {
        let url = try XCTUnwrap(
            FronteggResources.bundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            "PrivacyInfo.xcprivacy is missing from the FronteggSwift resource bundle",
            file: file,
            line: line
        )
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(plist as? [String: Any], file: file, line: line)
    }

    func test_manifest_declaresNoTracking() throws {
        let manifest = try loadManifest()

        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((manifest["NSPrivacyTrackingDomains"] as? [String])?.isEmpty, true)
    }

    func test_manifest_declaresUserDefaultsWithAppOnlyReason() throws {
        let manifest = try loadManifest()
        let apiTypes = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])

        let userDefaults = try XCTUnwrap(apiTypes.first {
            $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults"
        })
        XCTAssertEqual(userDefaults["NSPrivacyAccessedAPITypeReasons"] as? [String], ["CA92.1"])
    }

    func test_manifest_collectedDataTypesAreWellFormedAndNotUsedForTracking() throws {
        let manifest = try loadManifest()
        let collected = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])

        XCTAssertFalse(collected.isEmpty)
        for entry in collected {
            XCTAssertNotNil(entry["NSPrivacyCollectedDataType"] as? String)
            XCTAssertNotNil(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool)
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
            let purposes = try XCTUnwrap(entry["NSPrivacyCollectedDataTypePurposes"] as? [String])
            XCTAssertFalse(purposes.isEmpty)
        }
    }
}
