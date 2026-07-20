//
//  RefreshTokenMainThreadGuardTests.swift
//  FronteggSwiftTests
//
//  Regression coverage for FR-25925: the per-tenant branches of
//  refreshTokenWhenNeeded reloaded the tenant refresh token with an
//  unconditional `DispatchQueue.main.sync { ... }`. When the (only) caller —
//  applicationDidBecomeActive, which is @MainActor — is already on the main
//  thread, main.sync deadlocks the app.
//
//  The anti-deadlock decision is extracted into `FronteggAuth.applyOnMain`
//  so the "never main.sync when already on main" rule can be verified without
//  reproducing a real deadlock (which would hang the test runloop).
//

import XCTest
@testable import FronteggSwift

final class RefreshTokenMainThreadGuardTests: XCTestCase {

    func testApplyOnMain_whenAlreadyOnMainThread_runsWorkDirectlyWithoutDispatching() {
        var workRan = false
        var didDispatch = false

        FronteggAuth.applyOnMain(
            isMainThread: true,
            runSync: { work in
                didDispatch = true
                work()
            },
            work: { workRan = true }
        )

        XCTAssertTrue(workRan, "work should run")
        XCTAssertFalse(
            didDispatch,
            "must NOT dispatch onto main (main.sync) when already on the main thread — that deadlocks"
        )
    }

    func testApplyOnMain_whenOffMainThread_dispatchesOntoMainSynchronously() {
        var workRan = false
        var didDispatch = false

        FronteggAuth.applyOnMain(
            isMainThread: false,
            runSync: { work in
                didDispatch = true
                work()
            },
            work: { workRan = true }
        )

        XCTAssertTrue(didDispatch, "off the main thread it must dispatch onto main")
        XCTAssertTrue(workRan, "work should run")
    }
}
