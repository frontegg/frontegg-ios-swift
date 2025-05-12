//
//  Logger.swift
//  
//
//  Created by David Frontegg on 22/01/2023.
//

import Foundation
import os

public class FeLogger {
    public enum Level: Int, Codable, CaseIterable {
        /// Appropriate for messages that contain information normally of use only when
        /// tracing the execution of a program.
        case trace = 0
        
        /// Appropriate for messages that contain information normally of use only when
        /// debugging a program.
        case debug = 1
        
        /// Appropriate for informational messages.
        case info = 2
        
        /// Appropriate for messages that are not error conditions, but more severe than
        /// `.notice`.
        case warning = 3
        
        /// Appropriate for error conditions.
        case error = 4
        
        /// Appropriate for critical error conditions that usually require immediate
        /// attention.
        ///
        /// When a `critical` message is logged, the logging backend (`LogHandler`) is free to perform
        /// more heavy-weight operations to capture system state (such as capturing stack traces) to facilitate
        /// debugging.
        case critical = 5
    }
    
    public var logLevel: FeLogger.Level  = Level.error
    public var label: String
    private let logger = Logger()
    
    init(label: String) {
        self.label = label
    }
    
    public func trace(_ message: String) {
        if logLevel.rawValue <= FeLogger.Level.trace.rawValue {
            self.logger.trace("TRACE  | \(self.label): \(message)")
        }
    }
    public func debug(_ message: String) {
        if logLevel.rawValue <= FeLogger.Level.debug.rawValue {
            self.logger.debug("DEBUG  | \(self.label): \(message)")
        }
    }
    public func info(_ message: String) {
        if logLevel.rawValue <= FeLogger.Level.info.rawValue {
            self.logger.info("INFO   | \(self.label): \(message)")
        }
    }
    public func warning(_ message: String) {
        if logLevel.rawValue <= FeLogger.Level.warning.rawValue {
            self.logger.warning("WARNING | \(self.label): \(message)")
        }
    }
    public func error(_ message: String) {
        if logLevel.rawValue <= FeLogger.Level.error.rawValue {
            self.logger.error("ERROR   | \(self.label): \(message)")
        }
    }
    public func critical(_ message: String) {
        if logLevel.rawValue <= FeLogger.Level.critical.rawValue {
            self.logger.critical("CRITICAL| \(self.label): \(message)")
        }
    }
    
}


public func getLogger(_ className: String) -> FeLogger {
    let logger = FeLogger(label: className)
    logger.logLevel = PlistHelper.getLogLevel()
    return logger
}

