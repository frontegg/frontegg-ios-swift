//
//  EmbeddedLoginRootViewControllerTests.swift
//  FronteggSwiftTests
//
//  Regression coverage for FR-25926: embeddedLogin must never terminate the
//  host app (exit) when no root view controller is available. It should
//  surface `.couldNotFindRootViewController` through the completion handler.
//

import XCTest
import SwiftUI
@testable import FronteggSwift

private final class PresentingRootViewController: UIViewController {
    var stubPresented: UIViewController?
    override var presentedViewController: UIViewController? { stubPresented }
}

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
        auth?.testRootViewControllerOverride = nil
        auth?.loginCompletion = nil
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

    private func presentEmbeddedModalWithInFlightLogin() -> () -> Int {
        let root = PresentingRootViewController()
        root.stubPresented = UIHostingController(rootView: EmbeddedLoginModal(parentVC: nil))
        auth.testRootViewControllerOverride = root
        var firstCallerCompletions = 0
        auth.loginCompletion = { _ in firstCallerCompletions += 1 }
        return { firstCallerCompletions }
    }

    func testEmbeddedLoginWhileModalPresentedCompletesSecondCallerWithOperationCanceled() {
        let firstCallerCompletions = presentEmbeddedModalWithInFlightLogin()

        let completed = expectation(description: "second embeddedLogin completion is invoked")
        var receivedError: FronteggError?
        var completedOnMainThread = false

        auth.embeddedLogin({ result in
            completedOnMainThread = Thread.isMainThread
            if case .failure(let error) = result {
                receivedError = error
            }
            completed.fulfill()
        }, loginHint: nil)

        wait(for: [completed], timeout: 2.0)

        guard case .authError(.operationCanceled) = receivedError else {
            return XCTFail("Expected .operationCanceled, got \(String(describing: receivedError))")
        }
        XCTAssertEqual(receivedError?.category, .cancelled)
        XCTAssertTrue(completedOnMainThread)
        XCTAssertNotNil(auth.loginCompletion, "In-flight login completion must be preserved")
        XCTAssertEqual(firstCallerCompletions(), 0)
    }

    func testLoginAsyncWhileEmbeddedModalPresentedThrowsInsteadOfHanging() {
        let firstCallerCompletions = presentEmbeddedModalWithInFlightLogin()

        let finished = expectation(description: "loginAsync returns")
        var thrown: Error?
        let auth = self.auth!
        Task {
            do {
                _ = try await auth.loginAsync()
            } catch {
                thrown = error
            }
            finished.fulfill()
        }

        wait(for: [finished], timeout: 2.0)

        guard case .authError(.operationCanceled)? = thrown as? FronteggError else {
            return XCTFail("Expected .operationCanceled, got \(String(describing: thrown))")
        }
        XCTAssertEqual(firstCallerCompletions(), 0)
    }
}
