import XCTest
@testable import FronteggSwift

final class FronteggAuthResetForTestingTests: XCTestCase {
    func test_resolvedTestingResetHost_prefersOverride_andIgnoresLateInitPlaceholder() {
        let host = FronteggAuth.resolvedTestingResetHost(
            baseUrlOverride: "https://app-x4gr8g28fxr5.frontegg.com/oauth/prelogin",
            currentBaseUrl: "https://late-init.invalid",
            appBaseUrl: ""
        )

        XCTAssertEqual(host, "app-x4gr8g28fxr5.frontegg.com")
    }

    func test_resolvedTestingResetHost_fallsBackToCurrentBaseUrl() {
        let host = FronteggAuth.resolvedTestingResetHost(
            baseUrlOverride: nil,
            currentBaseUrl: "https://tenant-a.frontegg.com",
            appBaseUrl: ""
        )

        XCTAssertEqual(host, "tenant-a.frontegg.com")
    }

    func test_shouldRemoveTestingWebsiteDataRecord_matchesHostAndSubdomains() {
        XCTAssertTrue(
            FronteggAuth.shouldRemoveTestingWebsiteDataRecord(
                named: "app-x4gr8g28fxr5.frontegg.com",
                forHost: "app-x4gr8g28fxr5.frontegg.com"
            )
        )
        XCTAssertTrue(
            FronteggAuth.shouldRemoveTestingWebsiteDataRecord(
                named: "cdn.app-x4gr8g28fxr5.frontegg.com",
                forHost: "app-x4gr8g28fxr5.frontegg.com"
            )
        )
        XCTAssertFalse(
            FronteggAuth.shouldRemoveTestingWebsiteDataRecord(
                named: "example.com",
                forHost: "app-x4gr8g28fxr5.frontegg.com"
            )
        )
    }
}
