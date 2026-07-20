//
//  RefreshGateTests.swift
//  FronteggSwiftTests
//
//  Regression coverage for FR-25927: token-refresh entry must be atomic so
//  only one refresh runs at a time. The previous refreshingToken check-then-set
//  was non-atomic, letting two concurrent refreshes issue duplicate rotating-
//  refresh-token requests (the loser 401'd → credentials cleared → spurious
//  logout).
//

import XCTest
@testable import FronteggSwift

final class RefreshGateTests: XCTestCase {

    func testTryBegin_onlyOneOfManyConcurrentCallersMayBeginARefresh() async {
        let gate = RefreshGate()

        let winners = await withTaskGroup(of: Bool.self) { group -> Int in
            for _ in 0..<50 {
                group.addTask { await gate.tryBegin() }
            }
            var count = 0
            for await didBegin in group where didBegin {
                count += 1
            }
            return count
        }

        XCTAssertEqual(winners, 1, "exactly one concurrent caller may begin a refresh")
    }

    func testEnd_releasesTheSlotForASubsequentRefresh() async {
        let gate = RefreshGate()

        let first = await gate.tryBegin()
        XCTAssertTrue(first, "the first caller should begin")

        await gate.end()

        let second = await gate.tryBegin()
        XCTAssertTrue(second, "after end(), a subsequent caller may begin")
    }
}
