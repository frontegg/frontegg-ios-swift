//
//  FeatureFlags.swift
//  FronteggSwift
//
//  Created by David Antoon on 22/09/2025.
//

import Foundation

public class FeatureFlags {
    public static let mobileEnableLoggingKey = "mobile-enable-logging"

    public struct Config {
        public let clientId: String
        public let api: Api
        public let storage: UserDefaults
        public init(clientId: String, api: Api, storage: UserDefaults = .standard) {
            self.clientId = clientId;
            self.storage = storage;
            self.api = api
        }
    }

    // MARK: - State
    private let api: Api
    private let storage: UserDefaults
    private let storageKey: String
    public var ready: Bool { !_flags.isEmpty }

    private let logger = getLogger("FeatureFlags")
    // Thread-safe dictionary via concurrent queue: reads are sync, writes use barrier.
    private let q = DispatchQueue(label: "fflags.state", attributes: .concurrent)
    private var _flags: [String: Bool] = [:] // guarded by `q`

    // Backoff
    private let initialBackoff: TimeInterval = 0.5
    private let maxBackoff: TimeInterval = 30
    private let jitter: ClosedRange<Double> = 0.8...1.2

    // MARK: - Init (first run waits until loaded)
    public func start() async {
        logger.info("Initializing FeatureFlag store")
        if let cached = self.loadFromStorage() {
            logger.info("Loading FeatureFlags from cache")
            self.setFlags(cached)
            // Fire-and-forget background refresh (no retry if cache exists)
            Task { try? await self.refreshOnceAndSave() }
        } else {
            logger.info("No cache found, waiting to fetch")
            // No cache: block until fetched (with retry)
            _ = try? await self.fetchWithRetryUntilValid()
        }
    }

    init(_ config: Config) {
        self.api = config.api
        self.storage = config.storage
        self.storageKey = "featureflags:\(config.clientId)"
    }

    // MARK: - Public (sync) reads
    public func hasFlag(_ key: String) -> Bool {
        q.sync { _flags[key] != nil }
    }

    public func isOn(_ key: String) -> Bool {
        q.sync { _flags[key] == true }
    }

    // MARK: - Public (async) fetch trigger
    /// Call when user logs in or app returns to foreground.
    @discardableResult
    public func fetchFeatureFlags() async -> Bool {
        // If we already have any flags, do a single best-effort refresh (no retry).
        if hasAnyFlags {
            do { try await refreshOnceAndSave(); return true }
            catch { return true } // keep existing
        } else {
            // No flags yet: must ensure we end with valid flags.
            return (try? await fetchWithRetryUntilValid()) ?? false
        }
    }

    // MARK: - Internals
    private var hasAnyFlags: Bool { q.sync { !_flags.isEmpty } }

    private func setFlags(_ new: [String: Bool]) {
        q.async(flags: .barrier) { self._flags = new }
    }

    private func refreshOnceAndSave() async throws {
        let raw = try await api.getFeatureFlags()
        let parsed = try Self.parse(rawString: raw)
        setFlags(parsed)
        logger.info("Feature flags updated")
        self.saveToStorage(flags: parsed, storage: storage, key: storageKey)
    }

    private func fetchWithRetryUntilValid() async throws -> Bool {
        var backoff = initialBackoff
        while true {
            do {
                try await refreshOnceAndSave()
                return true
            } catch {
                if !self.hasValidCache(storage: storage, key: storageKey) {
                    let delay = backoff * Double.random(in: jitter)
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    backoff = min(backoff * 2, maxBackoff)
                    continue
                } else {
                    // Load cache and stop retrying.
                    if let cached = self.loadFromStorage() {
                        setFlags(cached)
                    }
                    return true
                }
            }
        }
    }

    // MARK: - Storage helpers
    private func saveToStorage(flags: [String: Bool], storage: UserDefaults, key: String) {
        if let data = try? JSONEncoder().encode(flags) { storage.set(data, forKey: key) }
    }
    private func loadFromStorage() -> [String: Bool]? {
        guard let data = self.storage.data(forKey: self.storageKey) else { return nil }
        return try? JSONDecoder().decode([String: Bool].self, from: data)
    }
    private func hasValidCache(storage: UserDefaults, key: String) -> Bool {
        loadFromStorage() != nil
    }

    // MARK: - Parsing
    private static func parse(rawString: String) throws -> [String: Bool] {
        guard let data = rawString.data(using: .utf8) else { throw URLError(.cannotDecodeRawData) }
        let decoded = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = decoded as? [String: String] else { throw URLError(.cannotParseResponse) }
        var result: [String: Bool] = [:]
        result.reserveCapacity(dict.count)
        for (k,v) in dict {
            switch v.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "on", "true":  result[k] = true
            case "off", "false": result[k] = false
            default: break
            }
        }
        return result
    }
}
