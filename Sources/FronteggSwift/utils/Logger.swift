//
//  Logger.swift
//  
//
//  Created by David Frontegg on 22/01/2023.
//

import Foundation
import os

/// Implement this protocol to receive Frontegg SDK log events.
///
/// The delegate is called synchronously on the originating thread. Retain your
/// delegate in app code, and dispatch any network or disk I/O off-thread.
///
/// `trace` and `debug` messages are forwarded as-is. `info`, `warning`,
/// `error`, and `critical` messages are sanitized before delivery.
public protocol FronteggLoggerDelegate: AnyObject {
    func fronteggSDK(didLog message: String, level: FeLogger.Level, tag: String)
}

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

    private static let delegateDispatchKey = "com.frontegg.felogger.delegate-dispatch"
    private static let redactedPlaceholder = "<redacted>"
    private static let redactedEmailPlaceholder = "<redacted-email>"
    private static let redactedUserIDPlaceholder = "<redacted-user-id>"
    private static let urlDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    private static let sensitiveKeyPattern = [
        "access_token",
        "refresh_token",
        "id_token",
        "device_token",
        "accessToken",
        "refreshToken",
        "idToken",
        "deviceToken",
        "code_verifier",
        "code_verifier_pkce",
        "token"
    ]
    .map(NSRegularExpression.escapedPattern(for:))
    .joined(separator: "|")
    private static var sensitiveValuePattern: String {
        "((?:\"(?:\(sensitiveKeyPattern))\"|'(?:\(sensitiveKeyPattern))'|(?:\(sensitiveKeyPattern)))\\s*[:=]\\s*[\"']?)([^\"'&,;\\s\\]\\}]+)([\"']?)"
    }

    /// Set this to receive all SDK log events, including events below the
    /// configured SDK log level. Assign before `FronteggApp.shared` to observe
    /// bootstrap logs as well.
    public static weak var delegate: FronteggLoggerDelegate?
    
    public var logLevel: FeLogger.Level  = Level.error
    public var label: String
    private let logger = Logger()
    
    init(label: String) {
        self.label = label
    }
    
    public func trace(_ message: String) {
        emit(level: .trace, message: message) { logger, label, message in
            logger.trace("TRACE  | \(label): \(message)")
        }
    }
    public func debug(_ message: String) {
        emit(level: .debug, message: message) { logger, label, message in
            logger.debug("DEBUG  | \(label): \(message)")
        }
    }
    public func info(_ message: String) {
        emit(level: .info, message: message) { logger, label, message in
            logger.info("INFO   | \(label): \(message)")
        }
    }
    public func warning(_ message: String) {
        emit(level: .warning, message: message) { logger, label, message in
            logger.warning("WARNING | \(label): \(message)")
        }
    }
    public func error(_ message: String) {
        emit(level: .error, message: message) { logger, label, message in
            logger.error("ERROR   | \(label): \(message)")
        }
    }
    public func critical(_ message: String) {
        emit(level: .critical, message: message) { logger, label, message in
            logger.critical("CRITICAL| \(label): \(message)")
        }
    }

    private func emit(level: FeLogger.Level, message: String, osLog: (Logger, String, String) -> Void) {
        if logLevel.rawValue <= level.rawValue {
            osLog(logger, label, message)
        }

        dispatchToDelegate(message: message, level: level)
    }

    private func dispatchToDelegate(message: String, level: FeLogger.Level) {
        guard let delegate = FeLogger.delegate else {
            return
        }
        guard !Self.isDispatchingDelegateCall else {
            return
        }

        let outboundMessage = Self.sanitizedDelegateMessage(message, for: level)
        Self.withDelegateDispatchGuard {
            delegate.fronteggSDK(didLog: outboundMessage, level: level, tag: label)
        }
    }

    private static var isDispatchingDelegateCall: Bool {
        (Thread.current.threadDictionary[delegateDispatchKey] as? Bool) == true
    }

    private static func withDelegateDispatchGuard(_ body: () -> Void) {
        Thread.current.threadDictionary[delegateDispatchKey] = true
        defer {
            Thread.current.threadDictionary.removeObject(forKey: delegateDispatchKey)
        }
        body()
    }

    static func sanitizedDelegateMessage(_ message: String, for level: FeLogger.Level) -> String {
        guard level.rawValue >= FeLogger.Level.info.rawValue else {
            return message
        }

        var sanitized = redactURLQueries(in: message)
        sanitized = replaceMatches(
            in: sanitized,
            pattern: #"\b(Bearer)\s+[A-Za-z0-9._~+\/=\-]+"#,
            replacementTemplate: "$1 \(redactedPlaceholder)"
        )
        sanitized = replaceMatches(
            in: sanitized,
            pattern: sensitiveValuePattern,
            replacementTemplate: "$1\(redactedPlaceholder)$3"
        )
        sanitized = replaceMatches(
            in: sanitized,
            pattern: #"((?:fe_(?:refresh|device)[A-Za-z0-9_-]*)\s*=\s*)([^;,\s]+)"#,
            replacementTemplate: "$1\(redactedPlaceholder)"
        )
        sanitized = replaceMatches(
            in: sanitized,
            pattern: #"((?:\bcode[ _-]?verifier(?:_pkce)?\b[^:=\n]{0,20}\bused\b[^:=\n]{0,20})[:=]\s*["']?)([^"'&,;\s\)\]\}]+)(["']?)"#,
            replacementTemplate: "$1\(redactedPlaceholder)$3"
        )
        sanitized = replaceMatches(
            in: sanitized,
            pattern: #"((?<!status\s)(?<!error\s)(?:\bcode\b|\bstate\b)\s*[:=]\s*["']?)([^"'&,;\s\)\]\}]+)(["']?)"#,
            replacementTemplate: "$1\(redactedPlaceholder)$3"
        )
        sanitized = replaceMatches(
            in: sanitized,
            pattern: #"((?:\buser[ _-]?id\b|\buserId\b|\buser\.id\b)(?:[^:=\n]{0,20})[:=]\s*["']?)([^"'&,;\s\)\]\}]+)(["']?)"#,
            replacementTemplate: "$1\(redactedUserIDPlaceholder)$3"
        )
        sanitized = replaceMatches(
            in: sanitized,
            pattern: #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#,
            replacementTemplate: redactedEmailPlaceholder
        )

        return sanitized
    }

    private static func redactURLQueries(in message: String) -> String {
        guard let urlDetector else {
            return message
        }

        var sanitized = message
        let fullRange = NSRange(message.startIndex..<message.endIndex, in: message)
        let matches = urlDetector.matches(in: message, range: fullRange)

        for match in matches.reversed() {
            guard let range = Range(match.range, in: sanitized) else {
                continue
            }

            let urlString = String(sanitized[range])
            let redactedURL = redactedURLString(for: urlString)
            sanitized.replaceSubrange(range, with: redactedURL)
        }

        return sanitized
    }

    private static func redactedURLString(for urlString: String) -> String {
        guard var components = URLComponents(string: urlString), components.query != nil else {
            return urlString
        }

        let fragment = components.fragment
        components.query = nil
        components.fragment = nil

        var redacted = components.string ?? urlString
        redacted += "?<redacted>"

        if let fragment, !fragment.isEmpty {
            redacted += "#\(fragment)"
        }

        return redacted
    }

    private static func replaceMatches(
        in message: String,
        pattern: String,
        replacementTemplate: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return message
        }

        let range = NSRange(message.startIndex..<message.endIndex, in: message)
        return regex.stringByReplacingMatches(in: message, range: range, withTemplate: replacementTemplate)
    }
}


public func getLogger(_ className: String) -> FeLogger {
    let logger = FeLogger(label: className)
    logger.logLevel = PlistHelper.getLogLevel()
    return logger
}
