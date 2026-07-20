//
//  EmbeddedLoginRootViewControllerTests.swift
//  FronteggSwiftTests
//
//  Regression coverage for FR-25926: embeddedLogin must never terminate the
//  host app (exit) when no root view controller is available. It should
//  surface `.couldNotFindRootViewController` through the completion handler.
//

import XCTest
@testable import FronteggSwift

final class EmbeddedLoginRootViewControllerTests: XCTestCase {

    private var auth: FronteggAuth!
    private var credentialManager: CredentialManager!

    override func setUp() {
        super.setUp()
        NetworkStatusMonitor._testReset()
        credentialManager = CredentialManager(serviceKey: "frontegg-embedded-rootvc-tests-\(UUID().uuidString)")
        auth = FronteggAuth(
            baseUrl: "https://test.example.com",
            clientId: "test-client-id",
            applicationId: nil,
            credentialManager: credentialManager,
            isRegional: false,
            regionData: [],
            embeddedMode: true,
            isLateInit: true,
            entitlementsEnabled: false
        )
        auth.setIsLoading(false)
        auth.setInitializing(false)
        auth.setShowLoader(false)
    }

    override func tearDown() {
        auth?.cancelScheduledTokenRefresh()
        auth = nil
        Thread.sleep(forTimeInterval: 0.1)
        NetworkStatusMonitor._testReset()
        credentialManager?.clear()
        credentialManager = nil
        super.tearDown()
    }

    func testEmbeddedLoginWithoutRootViewControllerReportsErrorViaCompletion() {
        // The headless SPM test host has no window / root view controller, so
        // getRootVC() returns nil — the exact condition that triggered exit(500).
        guard auth.getRootVC() == nil else {
            return XCTFail("Test host unexpectedly has a root view controller; cannot exercise the no-rootVC path")
        }

        let completed = expectation(description: "embeddedLogin completion is invoked")
        var receivedError: FronteggError?

        auth.embeddedLogin({ result in
            if case .failure(let error) = result {
                receivedError = error
            }
            completed.fulfill()
        }, loginHint: nil)

        wait(for: [completed], timeout: 2.0)

        guard case .authError(.couldNotFindRootViewController) = receivedError else {
            return XCTFail("Expected .couldNotFindRootViewController, got \(String(describing: receivedError))")
        }
    }
}
