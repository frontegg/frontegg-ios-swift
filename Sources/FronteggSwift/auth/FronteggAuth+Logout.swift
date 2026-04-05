//
//  FronteggAuth+Logout.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import Foundation
import WebKit

extension FronteggAuth {

    private func finalizeLoggedOutOfflineState(
        enableOfflineMode: Bool,
        preserveOfflineState: Bool
    ) async {
        guard enableOfflineMode else {
            await MainActor.run {
                self.setIsOfflineMode(false)
            }
            return
        }

        if preserveOfflineState {
            await MainActor.run {
                self.setIsOfflineMode(true)
            }
            self.logger.info("Logout preserved unauthenticated offline mode from the previous authenticated offline state")
            ensureOfflineMonitoringActive(emitInitialState: true)
            return
        }

        let initialNetworkAvailable = await NetworkStatusMonitor.isActive
        let settledOnline = await settleUnauthenticatedStartupConnectivity(
            initialNetworkAvailable: initialNetworkAvailable,
            debounceDelay: 0.1,
            recoveryProbeCount: 1,
            connectivityProbe: { [weak self] in
                guard let self = self else { return false }
                return await NetworkStatusMonitor.probeConfiguredReachability(
                    timeout: self.unauthenticatedStartupProbeTimeout
                )
            }
        )

        self.logger.info(
            "Logout settled unauthenticated connectivity \(settledOnline ? "online" : "offline")"
        )
        ensureOfflineMonitoringActive(emitInitialState: false)
    }

    public func logout(clearCookie: Bool = true, _ completion: FronteggAuth.LogoutHandler? = nil) {
        Task { @MainActor in
            self.logoutTransitionLock.withLock {
                self.logoutInProgress = true
            }
            defer {
                self.logoutTransitionLock.withLock {
                    self.logoutInProgress = false
                }
            }

            setIsLoading(true)

            // Try to reload from keychain if in-memory token is nil
            // This ensures we can invalidate the session on the server even if the token
            // was not loaded into memory (e.g., after app restart)
            let accessTokenForServerLogout = self.accessToken
            var refreshTokenForServerLogout = self.refreshToken
            if refreshTokenForServerLogout == nil {
                if let keychainToken = try? credentialManager.get(key: KeychainKeys.refreshToken.rawValue) {
                    self.logger.info("Reloaded refresh token from keychain for logout")
                    refreshTokenForServerLogout = keychainToken
                } else {
                    self.logger.warning("No refresh token found in memory or keychain. Server session may remain active.")
                }
            }

            // Preserve lastActiveTenantId when enableSessionPerTenant is enabled
            // This ensures each device maintains its own tenant context even after logout
            let config = try? PlistHelper.fronteggConfig()
            let enableSessionPerTenant = config?.enableSessionPerTenant ?? false
            let enableOfflineMode = config?.enableOfflineMode ?? false
            let wasOfflineBeforeLogout = self.isOfflineMode

            // Logout owns the connectivity transition. Stop current monitoring immediately so
            // stale callbacks cannot race while server logout or cookie cleanup is still running.
            cancelScheduledTokenRefresh()
            invalidateConnectivityObservers()
            stopOfflineMonitoring()

            if enableSessionPerTenant {
                let preservedTenantId = credentialManager.getLastActiveTenantId()
                self.logger.info("🔵 [SessionPerTenant] Preserving lastActiveTenantId (\(preservedTenantId ?? "nil")) for per-tenant session isolation")
                // Clear all items except lastActiveTenantId
                self.credentialManager.clear(excludingKeys: [KeychainKeys.lastActiveTenantId.rawValue])
                self.logger.info("🔵 [SessionPerTenant] Cleared keychain while preserving lastActiveTenantId")
            } else {
                self.credentialManager.deleteLastActiveTenantId()
                self.credentialManager.clear()
            }
            CredentialManager.clearPendingOAuthFlows()
            SocialLoginUrlGenerator.shared.clearPendingSocialCodeVerifiers()

            await self.serverLogoutWithTimeout(accessToken: accessTokenForServerLogout, refreshToken: refreshTokenForServerLogout)

            if clearCookie {
                await self.clearCookieWithTimeout()
            }

            setIsAuthenticated(false)
            setUser(nil)
            setAccessToken(nil)
            setRefreshToken(nil)
            setInitializing(false)
            setAppLink(false)
            self.isLoginInProgress = false
            setRefreshingToken(false)
            setIsStepUpAuthorization(false)
            self.lastAttemptReason = nil
            entitlements.clear()

            await self.finalizeLoggedOutOfflineState(
                enableOfflineMode: enableOfflineMode,
                preserveOfflineState: wasOfflineBeforeLogout
            )

            setIsLoading(false)
            completion?(.success(true))
        }

    }

    /// Returns true if `domain` matches `host`, supporting leading dot and subdomains.
    @inline(__always)
    func cookieDomain(_ domain: String, matches host: String) -> Bool {
        let cd = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        return host == cd || host.hasSuffix("." + cd)
    }

    /// Builds a regex-based name matcher using `self.cookieRegex`.
    /// Falls back to `^fe_refresh` if empty or invalid.
    func makeCookieNameMatcher() -> (String) -> Bool {
        let fallback = "^fe_refresh"

        var cookieRegex: String?
        if let config = try? PlistHelper.fronteggConfig() {
            cookieRegex = config.cookieRegex
        }

        let pattern = (cookieRegex != nil && cookieRegex?.isEmpty == false) ? cookieRegex! : fallback
        do {
            let re = try NSRegularExpression(pattern: pattern)
            return { name in
                let range = NSRange(name.startIndex..<name.endIndex, in: name)
                return re.firstMatch(in: name, range: range) != nil
            }
        } catch {
            self.logger.warning("Invalid cookie regex '\(pattern)'. Using fallback '\(fallback)'. Error: \(error.localizedDescription)")
            let re = try! NSRegularExpression(pattern: fallback)
            return { name in
                let range = NSRange(name.startIndex..<name.endIndex, in: name)
                return re.firstMatch(in: name, range: range) != nil
            }
        }
    }


    /// Deletes cookies that match the configured name regex and (optionally) the current host.
    /// - Behavior:
    ///   - If `deleteCookieForHostOnly == true`, restricts deletion to cookies whose domain matches `baseUrl`'s host.
    ///   - If `deleteCookieForHostOnly == false`, deletes any cookie whose name matches the regex (domain-agnostic).
    /// - Awaited to guarantee that deletion completes before continuing logout flow.
    @MainActor
    func clearCookie() async {

        var deleteCookieForHostOnly: Bool = true
        var cookieRegex: String?
        if let config = try? PlistHelper.fronteggConfig() {
            deleteCookieForHostOnly = config.deleteCookieForHostOnly
            cookieRegex = config.cookieRegex
        }

        let restrictToHost = deleteCookieForHostOnly

        // Resolve host only when needed
        let host: String? = {
            guard restrictToHost else { return nil }
            guard let h = URL(string: baseUrl)?.host else {
                logger.warning("Invalid baseUrl; cannot resolve host. Proceeding without domain restriction.")
                return nil
            }
            return h
        }()

        let store = WKWebsiteDataStore.default().httpCookieStore

        // Fetch all cookies
        let cookies: [HTTPCookie] = await withCheckedContinuation { (cont: CheckedContinuation<[HTTPCookie], Never>) in
            store.getAllCookies { cont.resume(returning: $0) }
        }

        // Deduplicate defensively (name+domain+path is the natural identity)
        let uniqueCookies: [HTTPCookie] = {
            var seen = Set<String>()
            return cookies.filter { c in
                let key = "\(c.name)|\(c.domain)|\(c.path)"
                return seen.insert(key).inserted
            }
        }()

        let nameMatches = makeCookieNameMatcher()

        // Compose predicate
        let shouldDelete: (HTTPCookie) -> Bool = { cookie in
            guard nameMatches(cookie.name) else { return false }
            guard let h = host else { return true } // no domain restriction
            let match = self.cookieDomain(cookie.domain, matches: h)
            if !match {
                self.logger.debug("Skipping cookie due to domain mismatch: \(cookie.name) @ \(cookie.domain) (host: \(h))")
            }
            return match
        }

        let targets = uniqueCookies.filter(shouldDelete)

        guard targets.isEmpty == false else {
            self.logger.debug("No cookies matched for deletion. regex: \(cookieRegex ?? "^fe_refresh"), restrictToHost: \(restrictToHost), host: \(host ?? "n/a")")
            return
        }

        // Delete sequentially (deterministic, avoids overloading store).
        var deleted = 0
        let start = Date()

        for cookie in targets {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                store.delete(cookie) {
                    deleted += 1
                    self.logger.info("Deleted cookie [\(deleted)/\(targets.count)]: \(cookie.name) @ \(cookie.domain)\(cookie.path)")
                    cont.resume()
                }
            }
        }

        let elapsed = String(format: "%.2fs", Date().timeIntervalSince(start))
        self.logger.info("Cookie cleanup completed. Deleted \(deleted)/\(targets.count) cookies in \(elapsed).")
    }

    /// Server logout with timeout — silently continues if the request hangs or fails.
    private func serverLogoutWithTimeout(accessToken: String?, refreshToken: String?, timeout: TimeInterval = 5) async {
        final class OnceGuard: @unchecked Sendable {
            private let lock = NSLock()
            private var fired = false
            func tryFire() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                guard !fired else { return false }
                fired = true
                return true
            }
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let guard_ = OnceGuard()

            Task {
                await self.api.logout(accessToken: accessToken, refreshToken: refreshToken)
                if guard_.tryFire() { cont.resume() }
            }

            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if guard_.tryFire() {
                    self?.logger.warning("Server logout timed out after \(timeout)s — proceeding with local cleanup")
                    cont.resume()
                }
            }
        }
    }

    /// Wraps `clearCookie()` with a timeout to prevent the logout flow from hanging
    /// if `WKHTTPCookieStore` callbacks are never delivered (e.g., WebKit process terminated).
    @MainActor
    private func clearCookieWithTimeout(timeout: TimeInterval = 5) async {
        final class OnceGuard: @unchecked Sendable {
            private let lock = NSLock()
            private var fired = false
            func tryFire() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                guard !fired else { return false }
                fired = true
                return true
            }
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let guard_ = OnceGuard()

            Task { @MainActor in
                await self.clearCookie()
                if guard_.tryFire() { cont.resume() }
            }

            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if guard_.tryFire() {
                    self?.logger.warning("Cookie clearing timed out after \(timeout)s — proceeding with logout")
                    cont.resume()
                }
            }
        }
    }

    public func logout() {
        logout { res in
            self.logger.info("Logged out")
        }
    }
}
