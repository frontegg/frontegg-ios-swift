//
//  NetworkStatusMonitor.swift
//
//  Created by Nick Hagi on 18/09/2024.
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
        if http.statusCode == 408 { return true }            // Request Timeout
        if (300..<400).contains(http.statusCode) { return true } // likely captive portal
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
    private static var _onChangeHandlers: [((Bool) -> Void)] = []
    private static let stateLock = NSLock()
    
    /// Register an additional on-change handler at runtime.
    /// The handler is invoked on the main queue whenever the state changes,
    /// and also on the first emission after `startBackgroundMonitoring(...)`.
    /// - Returns: The index token you can keep if you want to remove it later via `removeOnChange(at:)`.
    @discardableResult
    public static func addOnChange(_ handler: @escaping (Bool) -> Void) -> Int {
        stateLock.lock()
        _onChangeHandlers.append(handler)
        let idx = _onChangeHandlers.count - 1
        stateLock.unlock()
        return idx
    }

    /// Remove a previously added handler using the index returned from `addOnChange`.
    /// If the index is out of bounds or already removed, this is a no-op.
    public static func removeOnChange(at index: Int) {
        stateLock.lock()
        if _onChangeHandlers.indices.contains(index) {
            _onChangeHandlers.remove(at: index)
        }
        stateLock.unlock()
    }

    /// Remove all registered handlers.
    public static func removeAllOnChangeHandlers() {
        stateLock.lock()
        _onChangeHandlers.removeAll()
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
        // Store the handler if provided
        if let handler = onChange {
            stateLock.lock()
            _onChangeHandlers.append(handler)
            stateLock.unlock()
        }

        // Retain the path monitor
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            if path.status != .satisfied {
                updateCached(false)
            } else if let base = configuredBaseURLString {
                Task {
                    let ok = await checkServerConnectivity(baseURLString: base)
                    updateCached(ok)
                }
            } else {
                updateCached(true) // route-only success
            }
        }
        monitor.start(queue: pathQueue)
        pathMonitor = monitor

        // Periodic active probe (only if strict mode is configured)
        backgroundTimer?.cancel()
        if configuredBaseURLString != nil {
            let t = DispatchSource.makeTimerSource(queue: backgroundQueue)
            t.schedule(deadline: .now() + 0.1, repeating: interval)
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

        // Emit an initial value immediately
        Task {
            if let base = configuredBaseURLString {
                let ok = await checkServerConnectivity(baseURLString: base)
                updateCached(ok, forceEmit: true)
            } else {
                let route = await routeIsAvailableOnce()
                updateCached(route, forceEmit: true)
            }
        }
    }

    public static func stopBackgroundMonitoring() {
        backgroundTimer?.cancel()
        backgroundTimer = nil
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    /// Keeps your existing call site: `guard await NetworkStatusMonitor.isActive else { ... }`
    public static var isActive: Bool {
        get async {
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
            handlersCopy = _onChangeHandlers // copy under lock
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
