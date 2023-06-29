//
//  Logger.swift
//  
//
//  Created by David Frontegg on 22/01/2023.
//

import Foundation

public class Logger {
    public enum Level: String, Codable, CaseIterable {
        /// Appropriate for messages that contain information normally of use only when
        /// tracing the execution of a program.
        case trace
        
        /// Appropriate for messages that contain information normally of use only when
        /// debugging a program.
        case debug
        
        /// Appropriate for informational messages.
        case info
        
        /// Appropriate for messages that are not error conditions, but more severe than
        /// `.notice`.
        case warning
        
        /// Appropriate for error conditions.
        case error
        
        /// Appropriate for critical error conditions that usually require immediate
        /// attention.
        ///
        /// When a `critical` message is logged, the logging backend (`LogHandler`) is free to perform
        /// more heavy-weight operations to capture system state (such as capturing stack traces) to facilitate
        /// debugging.
        case critical
    }
    
    public var logLevel: Logger.Level  = Level.error
    public var label: String
    
    init(label: String) {
        self.label = label
    }
    
    public func trace(_ message: String) {
        if logLevel.rawValue < Logger.Level.trace.rawValue {
            print("TRACE  | \(label): \(message)")
        }
    }
    public func debug(_ message: String) {
        if logLevel.rawValue < Logger.Level.debug.rawValue {
            print("DEBUG  | \(label): \(message)")
        }
    }
    public func info(_ message: String) {
        if logLevel.rawValue < Logger.Level.info.rawValue {
            print("INFO   | \(label): \(message)")
        }
    }
    public func warning(_ message: String) {
        if logLevel.rawValue < Logger.Level.warning.rawValue {
            print("WARNING | \(label): \(message)")
        }
    }
    public func error(_ message: String) {
        if logLevel.rawValue < Logger.Level.error.rawValue {
            print("ERROR   | \(label): \(message)")
        }
    }
    public func critical(_ message: String) {
        if logLevel.rawValue < Logger.Level.critical.rawValue {
            print("CRITICAL| \(label): \(message)")
        }
    }
    
}


public func getLogger(_ className: String) -> Logger {
    let logger = Logger(label: className)
    logger.logLevel = PlistHelper.getLogLevel()
    return logger
}

