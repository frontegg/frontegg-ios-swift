//
//  NetworkStatusMonitor.swift
//
//  Created by Nick Hagi on 18/09/2024.
//  Updated: Fix handler removal by switching to stable tokens under the hood,
//  while preserving the original index-based API without index-shift bugs.
//

import Foundation
import Network

// MARK: - Error classification

/// Walk the NSUnderlyingErrorKey chain to the deepest NSError.
private func deepestNSError(_ error: Error) -> NSError {
    var nsError = error as NSError
    while let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
        nsError = underlying
    }
    return nsError
}

/// Returns true if the error is very likely due to connectivity / transport problems.
/// You can optionally pass the URLResponse (if you have it) for extra signals.
func isConnectivityError(_ error: Error, response: URLResponse? = nil) -> Bool {
    let e = deepestNSError(error)

    // 1) Classic URL errors
    if e.domain == NSURLErrorDomain {
        let code = URLError.Code(rawValue: e.code) // not optional
        switch code {
        case .notConnectedToInternet,          // -1009
             .timedOut,                        // -1001
             .cannotFindHost,                  // -1003
             .cannotConnectToHost,             // -1004
             .networkConnectionLost,           // -1005
             .dnsLookupFailed,                 // -1006
             .secureConnectionFailed,          // -1200
             .serverCertificateHasBadDate,     // -1201
             .serverCertificateUntrusted,      // -1202
             .serverCertificateHasUnknownRoot, // -1203
             .serverCertificateNotYetValid,    // -1204
             .clientCertificateRejected,       // -1205
             .clientCertificateRequired,       // -1206
             .cannotLoadFromNetwork,           // -2000
             .internationalRoamingOff,         // -1018
             .dataNotAllowed,                  // -1020
             .callIsActive,                    // -1019
             .httpTooManyRedirects:            // -1007 (captive portal loops)
            return true
        case .cancelled:
            break
        default:
            break
        }
    }

    // 2) CFNetwork lower-level host/proxy/DNS errors
    if e.domain == (kCFErrorDomainCFNetwork as String) {
        // Host resolution errors (kCFHostErrorUnknown..kCFHostErrorNoAddress)
        if (-72000...(-71990)).contains(e.code) { return true }
        // SOCKS / proxy / HTTP proxy connection failures (broadly treat as connectivity)
        if (-12000...(-11800)).contains(e.code) { return true }
    }

    // 3) POSIX-level transport failures (e.g., ECONNRESET, ETIMEDOUT)
    if e.domain == NSPOSIXErrorDomain {
        let posix = POSIXError.Code(rawValue: Int32(e.code))
        switch posix {
        case .ECONNRESET, .ECONNABORTED, .ETIMEDOUT, .EHOSTDOWN, .EHOSTUNREACH,
             .ENETDOWN, .ENETUNREACH, .ENETRESET, .ESHUTDOWN, .EPIPE:
            return true
        default:
            break
        }
    }

    // 4) Optional HTTP-level signal (when you have the response)
    if let http = response as? HTTPURLResponse {
        if http.statusCode == 408 { return true }                  // Request Timeout
        if (300..<400).contains(http.statusCode) { return true }   // likely captive portal
    }

    return false
}

// MARK: - Active probe to a specific HTTPS server

private func checkServerConnectivity(
    baseURLString: String,
    timeout: TimeInterval = 3,
    treatRedirectsAsOffline: Bool = true
) async -> Bool {
    guard var comps = URLComponents(string: baseURLString) else { return false }
    if comps.scheme == nil { comps.scheme = "https" }
    if comps.scheme?.lowercased() != "https" { return false } // enforce https
    guard let url = comps.url else { return false }

    let cfg = URLSessionConfiguration.ephemeral
    cfg.timeoutIntervalForRequest = timeout
    cfg.timeoutIntervalForResource = timeout
    cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
    cfg.allowsExpensiveNetworkAccess = true
    cfg.allowsConstrainedNetworkAccess = true
    let session = URLSession(configuration: cfg)

    // 1) Try HEAD
    var head = URLRequest(url: url)
    head.httpMethod = "HEAD"
    head.cachePolicy = .reloadIgnoringLocalCacheData
    head.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
    head.setValue("close", forHTTPHeaderField: "Connection")

    do {
        let (_, resp) = try await session.data(for: head)
        if let http = resp as? HTTPURLResponse {
            if http.statusCode == 200 { return true }
            if (300..<400).contains(http.statusCode) { return !treatRedirectsAsOffline }
            return false
        }
        return false
    } catch {
        // If clearly transport/TLS/DNS → offline. Else some servers reject HEAD; try GET.
        if isConnectivityError(error) { return false }
    }

    // 2) Fallback: tiny GET
    var get = URLRequest(url: url)
    get.httpMethod = "GET"
    get.cachePolicy = .reloadIgnoringLocalCacheData
    get.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
    get.setValue("bytes=0-0", forHTTPHeaderField: "Range") // minimize payload
    get.setValue("close", forHTTPHeaderField: "Connection")

    do {
        let (_, resp) = try await session.data(for: get)
        guard let http = resp as? HTTPURLResponse else { return false }
        if http.statusCode == 200 || http.statusCode == 206 { return true }
        if (300..<400).contains(http.statusCode) { return !treatRedirectsAsOffline }
        return false
    } catch {
        return false
    }
}

// MARK: - Public facade

public enum NetworkStatusMonitor {
    // Configuration
    private static var configuredBaseURLString: String?

    // Strong refs (retain these!)
    private static var pathMonitor: NWPathMonitor?
    private static let pathQueue = DispatchQueue(label: "NetworkStatusMonitor.path")
    private static var backgroundTimer: DispatchSourceTimer?
    private static let backgroundQueue = DispatchQueue(label: "NetworkStatusMonitor.probe")

    // Cached state for background monitoring
    private static var _cachedReachable = false
    private static var _hasInitialCheckFired = false
    private static let _initialCheckLock = NSLock()
    private static var _isMonitoringActive = false
    private static let _monitoringLock = NSLock()
    private static var _initialCheckTask: Task<Void, Never>?

    // MARK: Handler storage (token-backed) + stable index mapping
    public struct OnChangeToken: Hashable { fileprivate let id = UUID() }

    /// All handlers keyed by stable token.
    private static var _onChangeHandlers: [OnChangeToken: (Bool) -> Void] = [:]

    /// Stable index map: each position holds the token that was returned at that index.
    /// We never shrink this array on removal; we set positions to `nil` to keep indices stable.
    private static var _indexMap: [OnChangeToken?] = []

    private static let stateLock = NSLock()

    // MARK: - Public API

    /// Register an additional on-change handler at runtime.
    /// The handler is invoked on the main queue whenever the state changes,
    /// and also on the first emission after `startBackgroundMonitoring(...)`.
    /// - Returns: An **index token** compatible with legacy `removeOnChange(at:)`.
    @discardableResult
    public static func addOnChange(_ handler: @escaping (Bool) -> Void) -> Int {
        stateLock.lock()
        let token = OnChangeToken()
        _onChangeHandlers[token] = handler
        _indexMap.append(token)
        let idx = _indexMap.count - 1
        stateLock.unlock()
        return idx
    }

    /// Modern API: add a handler and get a **stable token** for removal.
    @discardableResult
    public static func addOnChangeReturningToken(_ handler: @escaping (Bool) -> Void) -> OnChangeToken {
        stateLock.lock()
        let token = OnChangeToken()
        _onChangeHandlers[token] = handler
        _indexMap.append(token) // also track in index map so legacy indices remain aligned
        stateLock.unlock()
        return token
    }

    /// Remove a previously added handler using the **stable token**.
    public static func removeOnChange(_ token: OnChangeToken) {
        stateLock.lock()
        _onChangeHandlers.removeValue(forKey: token)
        // Null-out the first matching index position to preserve index stability for others.
        if let i = _indexMap.firstIndex(where: { $0 == token }) {
            _indexMap[i] = nil
        }
        stateLock.unlock()
    }

    /// Legacy removal: remove by **index** returned from `addOnChange(_:)`.
    /// Indices remain valid even if earlier handlers are removed (we never shift the map).
    public static func removeOnChange(at index: Int) {
        stateLock.lock()
        if _indexMap.indices.contains(index), let token = _indexMap[index] {
            _indexMap[index] = nil
            _onChangeHandlers.removeValue(forKey: token)
        }
        stateLock.unlock()
    }

    /// Remove all registered handlers.
    public static func removeAllOnChangeHandlers() {
        stateLock.lock()
        _onChangeHandlers.removeAll()
        _indexMap.removeAll()
        stateLock.unlock()
    }

    /// Require strict server reachability (TLS + response) for `isActive`.
    public static func configure(baseURLString: String) {
        configuredBaseURLString = baseURLString
    }

    /// Start background monitoring and receive callbacks on changes (and once immediately).
    public static func startBackgroundMonitoring(
        interval: TimeInterval = 10,
        onChange: ((Bool) -> Void)? = nil
    ) {
        // Prevent multiple simultaneous starts - check and set flag atomically
        _monitoringLock.lock()
        if _isMonitoringActive {
            _monitoringLock.unlock()
            return // Already monitoring, skip duplicate start
        }
        _isMonitoringActive = true
        _monitoringLock.unlock()
        
        // Stop any existing monitoring resources (defensive cleanup)
        backgroundTimer?.cancel()
        backgroundTimer = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        
        // Store the handler if provided (keeps legacy index-based behavior intact)
        if let handler = onChange {
            _ = addOnChange(handler)
        }

        // Reset initial check flag for new monitoring session
        _initialCheckLock.lock()
        _hasInitialCheckFired = false
        _initialCheckLock.unlock()
        
        // Cancel any pending initial check task
        _initialCheckTask?.cancel()
        _initialCheckTask = nil
        
        // Retain the path monitor
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            // Use lock to safely check and set the initial check flag atomically
            // This prevents duplicate /test calls when NWPathMonitor fires multiple times rapidly
            var shouldMakeInitialCheck = false
            _monitoringLock.lock()
            if !_hasInitialCheckFired && _initialCheckTask == nil {
                _hasInitialCheckFired = true
                shouldMakeInitialCheck = true
            }
            _monitoringLock.unlock()
            
            // Only make /test call if this is the initial fire
            if shouldMakeInitialCheck {
                // This is the initial check - make the /test call
                if path.status != .satisfied {
                    updateCached(false, forceEmit: true)
                } else if let base = configuredBaseURLString {
                    // Create the task and store it atomically
                    _monitoringLock.lock()
                    // Double-check that task doesn't exist (race condition protection)
                    if _initialCheckTask == nil {
                        _initialCheckTask = Task {
                            let ok = await checkServerConnectivity(baseURLString: base)
                            updateCached(ok, forceEmit: true)
                            // Clear the task reference when done
                            _monitoringLock.lock()
                            _initialCheckTask = nil
                            _monitoringLock.unlock()
                        }
                    }
                    _monitoringLock.unlock()
                } else {
                    updateCached(true, forceEmit: true) // route-only success
                }
            } else {
                // No base URL configured, just use path status
                updateCached(true)
            }
        }
        pathMonitor = monitor
        monitor.start(queue: pathQueue)

        // Periodic active probe (only if strict mode is configured)
        // Schedule timer to start after the full interval to avoid duplicate initial call
        // (pathUpdateHandler already provides the initial check when monitor.start() is called)
        if configuredBaseURLString != nil {
            let t = DispatchSource.makeTimerSource(queue: backgroundQueue)
            t.schedule(deadline: .now() + interval, repeating: interval)
            t.setEventHandler {
                guard let base = configuredBaseURLString else { return }
                Task {
                    let ok = await checkServerConnectivity(baseURLString: base)
                    updateCached(ok)
                }
            }
            t.resume()
            backgroundTimer = t
        } else {
            backgroundTimer = nil
        }
    }

    public static func stopBackgroundMonitoring() {
        _monitoringLock.lock()
        _isMonitoringActive = false
        _monitoringLock.unlock()
        _initialCheckTask?.cancel()
        _initialCheckTask = nil
        _initialCheckLock.lock()
        _hasInitialCheckFired = false
        _initialCheckLock.unlock()
        backgroundTimer?.cancel()
        backgroundTimer = nil
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    /// Keeps your existing call site: `guard await NetworkStatusMonitor.isActive else { ... }`
    public static var isActive: Bool {
        get async {
            // If background monitoring is active, use cached value to avoid duplicate /test calls
            // Background monitoring will keep the cache updated via periodic checks
            _monitoringLock.lock()
            let monitoringActive = _isMonitoringActive
            _monitoringLock.unlock()
            
            if monitoringActive {
                // Return cached value when background monitoring is active
                // This prevents duplicate /test calls during the initial monitoring phase
                stateLock.lock()
                let cached = _cachedReachable
                stateLock.unlock()
                return cached
            }
            
            // When monitoring is not active, perform a fresh check (on-demand)
            if let base = configuredBaseURLString {
                let ok = await checkServerConnectivity(baseURLString: base)
                updateCached(ok, forceEmit: true)
                return ok
            } else {
                let route = await routeIsAvailableOnce()
                updateCached(route, forceEmit: true)
                return route
            }
        }
    }

    // MARK: - Helpers

    /// Update cache and notify all registered handlers on the main queue if changed (or forced).
    private static func updateCached(_ value: Bool, forceEmit: Bool = false) {
        var changed = false
        var handlersCopy: [((Bool) -> Void)] = []

        stateLock.lock()
        changed = (value != _cachedReachable)
        _cachedReachable = value
        if changed || forceEmit {
            // Snapshot all current handlers (values) under lock
            handlersCopy = Array(_onChangeHandlers.values)
        }
        stateLock.unlock()

        guard changed || forceEmit else { return }
        guard !handlersCopy.isEmpty else { return }

        DispatchQueue.main.async {
            handlersCopy.forEach { $0(value) }
        }
    }

    private static func routeIsAvailableOnce() async -> Bool {
        await withCheckedContinuation { cont in
            let m = NWPathMonitor()
            m.pathUpdateHandler = { path in
                cont.resume(returning: path.status == .satisfied)
                m.cancel()
            }
            m.start(queue: pathQueue)
        }
    }
}
