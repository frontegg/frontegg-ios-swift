//
//  TraceIdLogger.swift
//
//  Created for Frontegg iOS SDK
//

import Foundation

class TraceIdLogger {
    static let shared = TraceIdLogger()
    
    private let maxTraceIds = 100
    private let fileName = "frontegg-trace-ids.log"
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.frontegg.traceIdLogger", attributes: .concurrent)
    
    private init() {}
    
    /// Logs a trace ID to the debug log file
    /// - Parameter traceId: The trace ID to log
    func logTraceId(_ traceId: String) {
        queue.async(flags: .barrier) {
            self._logTraceId(traceId)
        }
    }
    
    private func _logTraceId(_ traceId: String) {
        // Try to find project root from environment variables or use Documents directory as fallback
        let fileURL: URL
        
        // Check for Xcode environment variables that might contain the project path
        let env = ProcessInfo.processInfo.environment
        if let sourceRoot = env["SRCROOT"] {
            // Xcode sets SRCROOT to the project directory
            fileURL = URL(fileURLWithPath: sourceRoot).appendingPathComponent(fileName)
        } else if let projectDir = env["PROJECT_DIR"] {
            // Alternative: PROJECT_DIR environment variable
            fileURL = URL(fileURLWithPath: projectDir).appendingPathComponent(fileName)
        } else {
            // Fallback to Documents directory (accessible via Simulator file system)
            guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                print("❌ TraceIdLogger: Could not access documents directory")
                return
            }
            fileURL = documentsDirectory.appendingPathComponent(fileName)
            print("ℹ️ TraceIdLogger: Saving to Documents directory: \(fileURL.path)")
        }
        
        // Read existing trace IDs
        var traceIds: [String] = []
        if fileManager.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let content = String(data: data, encoding: .utf8) {
            traceIds = content.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        
        // Add new trace ID at the beginning (most recent first)
        traceIds.insert(traceId, at: 0)
        
        // Keep only the last maxTraceIds
        if traceIds.count > maxTraceIds {
            traceIds = Array(traceIds.prefix(maxTraceIds))
        }
        
        // Write back to file
        let content = traceIds.joined(separator: "\n")
        guard let data = content.data(using: .utf8) else {
            print("❌ TraceIdLogger: Failed to encode trace IDs to data")
            return
        }
        
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("❌ TraceIdLogger: Failed to write trace IDs to file: \(error)")
        }
    }
    
    /// Extracts and logs the frontegg-trace-id from an HTTP response
    /// - Parameter response: The URLResponse to extract trace ID from
    func extractAndLogTraceId(from response: URLResponse) {
        guard let httpResponse = response as? HTTPURLResponse else {
            return
        }
        
        guard let traceId = httpResponse.value(forHTTPHeaderField: "frontegg-trace-id") else {
            return
        }
        
        // Send trace IDs to Sentry as breadcrumbs (no-op when feature flag mobile-enable-logging is off)
        // This is useful for correlating client issues with server logs
        SentryHelper.addBreadcrumb(
            "frontegg-trace-id received",
            category: "network",
            level: .info,
            data: ["frontegg_trace_id": traceId]
        )
        
        // Also save to local file for debugging
        logTraceId(traceId)
    }
}

