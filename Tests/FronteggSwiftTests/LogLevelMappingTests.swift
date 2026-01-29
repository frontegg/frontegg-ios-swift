//
//  LogLevelMappingTests.swift
//  FronteggSwiftTests
//

import XCTest
@testable import FronteggSwift

final class LogLevelMappingTests: XCTestCase {

    func test_FeLoggerLevel_mapsFromFronteggPlistLogLevel_trace() {
        let level = FeLogger.Level(with: FronteggPlist.LogLevel.trace)
        XCTAssertEqual(level, .trace)
    }

    func test_FeLoggerLevel_mapsFromFronteggPlistLogLevel_debug() {
        let level = FeLogger.Level(with: FronteggPlist.LogLevel.debug)
        XCTAssertEqual(level, .debug)
    }

    func test_FeLoggerLevel_mapsFromFronteggPlistLogLevel_info() {
        let level = FeLogger.Level(with: FronteggPlist.LogLevel.info)
        XCTAssertEqual(level, .info)
    }

    func test_FeLoggerLevel_mapsFromFronteggPlistLogLevel_warn() {
        let level = FeLogger.Level(with: FronteggPlist.LogLevel.warn)
        XCTAssertEqual(level, .warning)
    }

    func test_FeLoggerLevel_mapsFromFronteggPlistLogLevel_error() {
        let level = FeLogger.Level(with: FronteggPlist.LogLevel.error)
        XCTAssertEqual(level, .error)
    }

    func test_FeLoggerLevel_mapsFromFronteggPlistLogLevel_critical() {
        let level = FeLogger.Level(with: FronteggPlist.LogLevel.critical)
        XCTAssertEqual(level, .critical)
    }
}
