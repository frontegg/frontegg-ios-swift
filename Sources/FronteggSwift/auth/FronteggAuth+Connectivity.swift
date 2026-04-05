//
//  FronteggAuth+Connectivity.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import Foundation
import UIKit
import Network

enum AuthenticatedStartupNetworkPathAssessment: String {
    case available = "available"
    case advisoryUnavailable = "advisory_unavailable"
    case forcedUnavailable = "forced_unavailable"
}

extension FronteggAuth {

    func startPostConnectivityServices() async {
        await self.featureFlags.start()
        SentryHelper.setSentryEnabledFromFeatureFlag(self.featureFlags.isOn(FeatureFlags.mobileEnableLoggingKey))
        await SocialLoginUrlGenerator.shared.reloadConfigs()
        self.warmingWebViewAsync()
    }

    @discardableResult
    func advanceConnectivityGeneration() -> UInt64 {
        connectivityGenerationLock.withLock {
            connectivityGeneration &+= 1
            return connectivityGeneration
        }
    }

    func isConnectivityGenerationCurrent(_ generation: UInt64) -> Bool {
        connectivityGenerationLock.withLock {
            connectivityGeneration == generation
        }
    }

    func cancelPendingOfflineDebounce() {
        offlineDebounceWork?.cancel()
        offlineDebounceWork = nil
    }

    func stopOfflineMonitoring() {
        NetworkStatusMonitor.stopBackgroundMonitoring()
        if let token = self.networkMonitoringToken {
            NetworkStatusMonitor.removeOnChange(token)
            self.networkMonitoringToken = nil
        }
    }

    func invalidateConnectivityObservers() {
        cancelPendingOfflineDebounce()
        _ = advanceConnectivityGeneration()
    }

    func clearTransientConnectivityStateAfterAuthenticatedSuccess() {
        invalidateConnectivityObservers()
        stopOfflineMonitoring()
        lastAttemptReason = nil
    }

    public func reconnectedToInternet(expectedGeneration: UInt64? = nil) {
        if let expectedGeneration,
           !isConnectivityGenerationCurrent(expectedGeneration) {
            return
        }

        // Always cancel a pending debounced offline transition first.
        // Quick reconnects during startup can otherwise leave a stale work item
        // that flips `isOfflineMode` to true after reachability has already recovered.
        cancelPendingOfflineDebounce()

        if(self.isOfflineMode == false){
            return;
        }
        self.logger.info("Connected to the internet")
        self.setIsOfflineMode(false)

        // Keep monitoring active — don't stop it here.
        // If refreshTokenIfNeeded() succeeds, $accessToken subscription stops monitoring.
        // If it fails, monitoring stays active to detect the next reconnection.

        Task {
            // Refresh tokens to get fresh tokens + re-fetch /me user data
            _ = await self.refreshTokenIfNeeded()
            await self.startPostConnectivityServices()
        }
    }
    public func disconnectedFromInternet(expectedGeneration: UInt64? = nil) {
        if let expectedGeneration,
           !isConnectivityGenerationCurrent(expectedGeneration) {
            return
        }

        self.logger.info("Disconnected from the internet (debounced)")
        // Debounce setting offline to avoid brief flicker on quick reconnects
        cancelPendingOfflineDebounce()
        let generation = expectedGeneration ?? connectivityGenerationLock.withLock { connectivityGeneration }
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard self.isConnectivityGenerationCurrent(generation) else { return }
            // Only set offline if still disconnected (best effort via lastAttemptReason or state)
            // We rely on reconnectedToInternet() to cancel this when path is back.
            self.setIsOfflineMode(true)
        }
        offlineDebounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + offlineDebounceDelay, execute: work)
    }

    @discardableResult
    func settleUnauthenticatedStartupConnectivity(
        initialNetworkAvailable: Bool,
        debounceDelay: TimeInterval? = nil,
        recoveryProbeCount: Int = 2,
        connectivityProbe: @escaping () async -> Bool
    ) async -> Bool {
        if initialNetworkAvailable {
            self.setIsOfflineMode(false)
            return true
        }

        let delay = debounceDelay ?? offlineDebounceDelay
        let attempts = max(recoveryProbeCount, 1)

        for _ in 0..<attempts {
            if delay > 0 {
                let nanos = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }

            let recovered = await connectivityProbe()
            if recovered {
                offlineDebounceWork?.cancel()
                offlineDebounceWork = nil
                self.setIsOfflineMode(false)
                return true
            }
        }

        self.setIsOfflineMode(true)
        return false
    }

    @discardableResult
    func completeUnauthenticatedStartupInitialization(
        monitoringInterval: TimeInterval,
        startupProbeTimeout: TimeInterval? = nil,
        offlineCommitWindow: TimeInterval? = nil,
        probeDelay: TimeInterval? = nil,
        connectivityProbe: ((TimeInterval) async -> Bool)? = nil,
        postConnectivityServices: (() async -> Void)? = nil
    ) async -> Bool {
        let probeTimeout = startupProbeTimeout ?? unauthenticatedStartupProbeTimeout
        let commitWindow = offlineCommitWindow ?? unauthenticatedStartupOfflineCommitWindow
        let retryDelay = probeDelay ?? unauthenticatedStartupProbeDelay
        let probe = connectivityProbe ?? { timeout in
            await NetworkStatusMonitor.probeConfiguredReachability(timeout: timeout)
        }
        let runPostConnectivityServices = postConnectivityServices ?? {
            await self.startPostConnectivityServices()
        }

        logger.info(
            "Starting unauthenticated startup connectivity race (window: \(commitWindow)s, probeTimeout: \(probeTimeout)s, retryDelay: \(retryDelay)s)"
        )

        offlineDebounceWork?.cancel()
        offlineDebounceWork = nil
        await MainActor.run {
            self.setIsOfflineMode(false)
        }

        let raceStart = Date()
        var probeCount = 0

        func performProbe() async -> Bool {
            probeCount += 1
            return await probe(probeTimeout)
        }

        var settledOnline = await performProbe()

        while !settledOnline {
            let remaining = commitWindow - Date().timeIntervalSince(raceStart)
            if remaining <= 0 {
                break
            }

            if retryDelay > 0 {
                let sleepSeconds = min(retryDelay, remaining)
                if sleepSeconds > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000))
                }
            }

            let remainingAfterDelay = commitWindow - Date().timeIntervalSince(raceStart)
            if remainingAfterDelay <= 0 {
                break
            }

            settledOnline = await performProbe()
        }

        logger.info(
            "Unauthenticated startup connectivity settled \(settledOnline ? "online" : "offline") after \(probeCount) probe(s)"
        )

        if settledOnline {
            await MainActor.run {
                self.setIsOfflineMode(false)
            }
            await runPostConnectivityServices()
        } else {
            await MainActor.run {
                self.setIsOfflineMode(true)
            }
        }

        ensureOfflineMonitoringActive(intervalOverride: monitoringInterval, emitInitialState: false)

        await MainActor.run {
            self.setIsLoading(false)
            self.setInitializing(false)
        }

        return settledOnline
    }

    func unwrapURLError(_ error: Error) -> URLError? {
        // Walk underlying errors to find a URLError
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return URLError(URLError.Code(rawValue: nsError.code))
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            if underlying.domain == NSURLErrorDomain {
                return URLError(URLError.Code(rawValue: underlying.code))
            }
            // One more level just in case the network error is double-wrapped
            if let deeper = underlying.userInfo[NSUnderlyingErrorKey] as? NSError, deeper.domain == NSURLErrorDomain {
                return URLError(URLError.Code(rawValue: deeper.code))
            }
        }
        return nil
    }



    // MARK: - Offline helpers

    /// Checks network path availability using NWPathMonitor with a timeout.
    /// Path checks are advisory only in restricted-network environments (e.g., aircraft with whitelisted domains).
    /// Actual HTTP request failures remain the authoritative source of truth.
    func checkNetworkPath(timeout: UInt64 = 500_000_000) async -> Bool {
#if DEBUG
        if let override = Self.testNetworkPathAvailabilityOverride {
            return override
        }
#endif
        return await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "NetworkPathCheck.\(UUID().uuidString)")
            final class ResumeState: @unchecked Sendable {
                private let lock = NSLock()
                private var hasResumed = false
                func tryResume() -> Bool {
                    return lock.withLock {
                        guard !hasResumed else { return false }
                        hasResumed = true
                        return true
                    }
                }
            }
            let resumeState = ResumeState()

            monitor.pathUpdateHandler = { path in
                guard resumeState.tryResume() else { return }
                let available = (path.status == .satisfied)
                monitor.cancel()
                continuation.resume(returning: available)
            }
            monitor.start(queue: queue)

            Task { [weak self] in
                try? await Task.sleep(nanoseconds: timeout)
                guard resumeState.tryResume() else { return }
                monitor.cancel()
                self?.logger.info("NWPathMonitor timed out after \(timeout / 1_000_000)ms — treating as offline (advisory)")
                continuation.resume(returning: false)
            }
        }
    }

    func assessAuthenticatedStartupNetworkPath(
        timeout: UInt64 = 500_000_000
    ) async -> AuthenticatedStartupNetworkPathAssessment {
#if DEBUG
        if let override = Self.testNetworkPathAvailabilityOverride {
            return override ? .available : .forcedUnavailable
        }
#endif

        let isNetworkAvailable = await checkNetworkPath(timeout: timeout)
        return isNetworkAvailable ? .available : .advisoryUnavailable
    }

    /// Resolves stored session artifacts (tokens, offline user, tenant) using consistent precedence:
    /// lastActiveTenantId → user.activeTenant → offlineUser.activeTenant → legacy global tokens.
    func resolveStoredSessionArtifacts(enableSessionPerTenant: Bool) -> StoredSessionArtifacts {
        var refreshToken: String? = nil
        var accessToken: String? = nil
        var tenantId: String? = nil

        if enableSessionPerTenant {
            tenantId = credentialManager.getLastActiveTenantId()
            if tenantId == nil, let user = self.user {
                tenantId = user.activeTenant.id
            }
            if tenantId == nil {
                if let offlineUser = credentialManager.getOfflineUser() {
                    tenantId = offlineUser.activeTenant.id
                }
            }

            if let tid = tenantId {
                refreshToken = try? credentialManager.getTokenForTenant(tenantId: tid, tokenType: .refreshToken)
                accessToken = try? credentialManager.getTokenForTenant(tenantId: tid, tokenType: .accessToken)
            }

            // Fallback to legacy tokens if both tenant-specific tokens are nil
            // Require BOTH legacy tokens to exist (matching initializeSubscriptions behavior)
            if refreshToken == nil && accessToken == nil {
                if let legacyRefresh = try? credentialManager.get(key: KeychainKeys.refreshToken.rawValue),
                   let legacyAccess = try? credentialManager.get(key: KeychainKeys.accessToken.rawValue) {
                    refreshToken = legacyRefresh
                    accessToken = legacyAccess
                }
            }
        } else {
            refreshToken = try? credentialManager.get(key: KeychainKeys.refreshToken.rawValue)
            accessToken = try? credentialManager.get(key: KeychainKeys.accessToken.rawValue)
        }

        let offlineUser = credentialManager.getOfflineUser()
        return StoredSessionArtifacts(accessToken: accessToken, refreshToken: refreshToken, offlineUser: offlineUser, tenantId: tenantId)
    }

    /// Shared state update for connectivity loss on manual refresh paths.
    /// Does NOT enqueue retries — scheduled refresh paths handle their own retry/backoff logic.
    func applyConnectivityLossState(enableOfflineMode: Bool) async {
        let hasTokens = (self.refreshToken != nil || self.accessToken != nil)
        guard hasTokens else { return }

        if enableOfflineMode {
            let resolvedUser = self.accessToken.flatMap { self.resolveBestEffortUser(accessToken: $0) }
                ?? self.user
                ?? self.credentialManager.getOfflineUser()
            if let resolvedUser, self.credentialManager.getOfflineUser() == nil {
                self.credentialManager.saveOfflineUser(user: resolvedUser)
            }
            await MainActor.run {
                self.setUser(resolvedUser)
                self.setInitializing(false)
                self.setIsAuthenticated(hasTokens)
                self.setIsOfflineMode(true)
                self.setIsLoading(false)
            }
        } else {
            await MainActor.run {
                self.setInitializing(false)
                self.setIsLoading(false)
                // Keep isOfflineMode=false — app didn't opt into offline UX
            }
        }
    }

    /// Manual refresh failures should preserve the cached session and rely on reconnect monitoring
    /// instead of spinning scheduled refresh retries against a disconnected or blocked network.
    func startOfflineMonitoringAfterManualConnectivityFailure(enableOfflineMode: Bool) {
        guard enableOfflineMode else { return }

        let hasTokens = (self.refreshToken != nil || self.accessToken != nil)
        guard hasTokens else { return }

        self.lastAttemptReason = .noNetwork
        self.logger.info("Manual refresh connectivity failure - canceling scheduled token refreshes and starting offline monitoring")
        self.cancelScheduledTokenRefresh()
        self.ensureOfflineMonitoringActive(emitInitialState: false)
    }

    // MARK: - Offline-like handler

    /// Centralized handler for errors that *behave like* no connectivity.
    /// Decides the backoff offset, updates state (including offline user), and reschedules.
    func handleOfflineLikeFailure(
        error: Error?,
        enableOfflineMode: Bool,
        attempts: Int,
        skipNetworkCheck: Bool = false
    ) async {
        // Classify error type
        let isConn = error.map { isConnectivityError($0) } ?? true // treat nil as connectivity (e.g., no active internet path)

        if isConn {
            self.logger.info("Refresh rescheduled due to network error \(error?.localizedDescription ?? "(no error)")")
        } else {
            self.logger.info("Refresh rescheduled due to unknown error \(error?.localizedDescription ?? "(no error)")")
        }

        // Classify lastAttemptReason based on actual error type
        self.lastAttemptReason = isConn ? .noNetwork : .unknown

        let hasTokens = (self.refreshToken != nil || self.accessToken != nil)
        self.logger.info("handleOfflineLikeFailure: isConn=\(isConn), enableOfflineMode=\(enableOfflineMode), hasTokens=\(hasTokens), attempts=\(attempts), lastAttemptReason=\(isConn ? ".noNetwork" : ".unknown")")

        if enableOfflineMode {
            let resolvedUser = self.accessToken.flatMap { self.resolveBestEffortUser(accessToken: $0) }
                ?? self.user
                ?? self.credentialManager.getOfflineUser()
            if let resolvedUser, self.credentialManager.getOfflineUser() == nil {
                self.credentialManager.saveOfflineUser(user: resolvedUser)
            }
            await MainActor.run {
                self.setUser(resolvedUser)
                self.setInitializing(false)
                self.setIsAuthenticated(hasTokens)
                self.setIsOfflineMode(true)
                self.setIsLoading(false)
            }

            // If we have tokens and we're offline, DON'T schedule token refreshes
            // This prevents repeated network calls when offline
            if hasTokens {
                self.logger.info("Offline with tokens - canceling scheduled token refreshes to avoid network abuse")
                self.cancelScheduledTokenRefresh()
                // Start monitoring so reconnectedToInternet() fires when network returns
                self.ensureOfflineMonitoringActive(emitInitialState: false)
                return // Don't schedule another refresh — monitoring will handle reconnection
            }
        } else if isConn {
            // enableOfflineMode=false but this is a connectivity error with valid tokens.
            // Preserve isAuthenticated; keep isOfflineMode=false (app didn't opt into offline UX).
            if hasTokens {
                self.logger.info("Connectivity error with valid tokens (offline mode not enabled). Preserving auth state, keeping isOfflineMode=false.")
                await MainActor.run {
                    self.setInitializing(false)
                    self.setIsLoading(false)
                }
            }
        }

        // When skipNetworkCheck is true and we have tokens, don't schedule refreshes
        // This prevents scheduled refreshes from calling isActive (which triggers /test calls)
        if skipNetworkCheck && hasTokens {
            self.logger.info("Skipping token refresh scheduling to avoid /test calls (offline with tokens)")
            return
        }

        // Exponential backoff for connectivity errors instead of fixed 2s intervals
        let retryOffset: TimeInterval
        if isConn {
            retryOffset = min(TimeInterval(pow(2.0, Double(min(attempts + 2, 6)))), 60)
        } else {
            retryOffset = 1 // non-connectivity errors retry quickly
        }
        self.logger.info("Scheduling retry in \(retryOffset)s (attempt \(attempts + 1), isConn: \(isConn))")
        scheduleTokenRefresh(offset: retryOffset, attempts: attempts + 1, skipNetworkCheck: skipNetworkCheck)
    }

    /// Starts network monitoring so that `reconnectedToInternet()` fires on a later connectivity transition.
    /// Safe to call multiple times — stops existing monitoring first to avoid duplicates.
    func ensureOfflineMonitoringActive(intervalOverride: TimeInterval? = nil, emitInitialState: Bool = false) {
        let config = try? PlistHelper.fronteggConfig()
        let monitoringInterval = intervalOverride ?? config?.networkMonitoringInterval ?? 10

        // Stop existing monitoring to avoid duplicates
        stopOfflineMonitoring()
        cancelPendingOfflineDebounce()
        let generation = advanceConnectivityGeneration()

        let token = NetworkStatusMonitor.addOnChangeReturningToken { [weak self] reachable in
            guard let self = self else { return }
            if reachable {
                self.reconnectedToInternet(expectedGeneration: generation)
            } else {
                self.disconnectedFromInternet(expectedGeneration: generation)
            }
        }
        self.networkMonitoringToken = token
        NetworkStatusMonitor.startBackgroundMonitoring(
            interval: monitoringInterval,
            emitInitialState: emitInitialState,
            onChange: nil
        )
        self.logger.info(
            "Started offline network monitoring (interval: \(monitoringInterval)s, emitInitialState: \(emitInitialState))"
        )
    }

    public func recheckConnection() {

        DispatchQueue.global(qos: .background).async {

            Task {
                guard await NetworkStatusMonitor.isActive else {
                    self.logger.info("No network connection")
                    return
                }

                if self.isOfflineMode {
                    let hasRuntimeSession = self.isAuthenticated
                        || self.accessToken != nil
                        || self.refreshToken != nil

                    if !hasRuntimeSession {
                        self.logger.info("Network is back, clearing unauthenticated offline state")
                        self.cancelPendingOfflineDebounce()
                        self.lastAttemptReason = nil
                        await MainActor.run {
                            self.setUser(nil)
                            self.setIsOfflineMode(false)
                            self.setIsLoading(false)
                            self.setWebLoading(false)
                            self.setInitializing(false)
                            self.setShowLoader(false)
                            self.setAppLink(false)
                            self.setExternalLink(false)
                        }
                        return
                    }

                    self.logger.info("Network is back, settling offline state through reconnect handling")
                    self.reconnectedToInternet()
                    return
                }

                self.logger.info("Network is back, refreshing...")
                _ = await self.refreshTokenIfNeeded()
            }
        }
    }
}
