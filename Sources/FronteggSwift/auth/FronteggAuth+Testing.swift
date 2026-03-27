//
//  FronteggAuth+Testing.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import Foundation
import WebKit

extension FronteggAuth {

#if DEBUG
    @MainActor
    func resetForTesting(baseUrlOverride: String? = nil) async {
        cancelScheduledTokenRefresh()
        offlineDebounceWork?.cancel()
        offlineDebounceWork = nil

        NetworkStatusMonitor.stopBackgroundMonitoring()
        if let token = networkMonitoringToken {
            NetworkStatusMonitor.removeOnChange(token)
            networkMonitoringToken = nil
        }

        if let activeSession = WebAuthenticator.shared.session {
            activeSession.cancel()
            WebAuthenticator.shared.session = nil
        }
        WebAuthenticator.shared.window = nil

        isInitializingWithTokens = false
        isLoginInProgress = false
        pendingAppLink = nil
        activeEmbeddedOAuthFlow = .login
        loginHint = nil
        loginCompletion = nil
        lastAttemptReason = nil
        webview = nil
        Self.testNetworkPathAvailabilityOverride = nil

        credentialManager.deleteLastActiveTenantId()
        credentialManager.clear()
        CredentialManager.clearPendingOAuthFlows()
        UserDefaults.standard.removeObject(forKey: KeychainKeys.region.rawValue)

        setIsAuthenticated(false)
        setUser(nil)
        setAccessToken(nil)
        setRefreshToken(nil)
        setInitializing(false)
        setShowLoader(false)
        setAppLink(false)
        setWebLoading(false)
        setLoginBoxLoading(false)
        setIsLoading(false)
        setIsOfflineMode(false)
        setRefreshingToken(false)
        setIsStepUpAuthorization(false)
        entitlements.clear()
        resetEntitlementsLoadState()

        await clearWebsiteDataForTesting(baseUrlOverride: baseUrlOverride)
        URLCache.shared.removeAllCachedResponses()
    }

    func setTestNetworkPathAvailabilityOverride(_ available: Bool?) {
        Self.testNetworkPathAvailabilityOverride = available
    }

    func hasScheduledTokenRefreshForTesting() -> Bool {
        refreshTokenDispatch != nil
    }

    @MainActor
    func isLoginInProgressForTesting() -> Bool {
        isLoginInProgress
    }
#endif

    @MainActor
    func clearWebsiteDataForTesting(baseUrlOverride: String?) async {
        let store = WKWebsiteDataStore.default()
        let allWebsiteDataTypes = WKWebsiteDataStore.allWebsiteDataTypes()

        guard let host = Self.resolvedTestingResetHost(
            baseUrlOverride: baseUrlOverride,
            currentBaseUrl: baseUrl,
            appBaseUrl: FronteggApp.shared.baseUrl
        ) else {
            logger.warning("resetForTesting could not resolve a scoped host, falling back to global WebKit data cleanup")
            await removeAllWebsiteData(store: store, websiteDataTypes: allWebsiteDataTypes)
            clearSharedCookiesForTesting(host: nil)
            return
        }

        let websiteDataTypes = Self.testingResetWebsiteDataTypes()
        logger.info("resetForTesting clearing scoped web data for host: \(host)")

        let records = await fetchWebsiteDataRecords(store: store, websiteDataTypes: websiteDataTypes)
        let matchingRecords = records.filter {
            Self.shouldRemoveTestingWebsiteDataRecord(named: $0.displayName, forHost: host)
        }

        if !matchingRecords.isEmpty {
            await removeWebsiteData(store: store, websiteDataTypes: websiteDataTypes, records: matchingRecords)
        }

        let storeCookies = await getAllCookies(store: store)
        for cookie in storeCookies where cookieDomain(cookie.domain, matches: host) {
            await deleteCookie(store: store, cookie: cookie)
        }

        clearSharedCookiesForTesting(host: host)
    }

    @MainActor
    func fetchWebsiteDataRecords(
        store: WKWebsiteDataStore,
        websiteDataTypes: Set<String>
    ) async -> [WKWebsiteDataRecord] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[WKWebsiteDataRecord], Never>) in
            store.fetchDataRecords(ofTypes: websiteDataTypes) { records in
                continuation.resume(returning: records)
            }
        }
    }

    @MainActor
    func removeWebsiteData(
        store: WKWebsiteDataStore,
        websiteDataTypes: Set<String>,
        records: [WKWebsiteDataRecord]
    ) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.removeData(ofTypes: websiteDataTypes, for: records) {
                continuation.resume()
            }
        }
    }

    @MainActor
    func removeAllWebsiteData(
        store: WKWebsiteDataStore,
        websiteDataTypes: Set<String>
    ) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.removeData(ofTypes: websiteDataTypes, modifiedSince: .distantPast) {
                continuation.resume()
            }
        }
    }

    @MainActor
    func getAllCookies(store: WKWebsiteDataStore) async -> [HTTPCookie] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[HTTPCookie], Never>) in
            store.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    @MainActor
    func deleteCookie(store: WKWebsiteDataStore, cookie: HTTPCookie) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.httpCookieStore.delete(cookie) {
                continuation.resume()
            }
        }
    }

    func clearSharedCookiesForTesting(host: String?) {
        let cookiesToDelete: [HTTPCookie]
        if let host, !host.isEmpty {
            cookiesToDelete = (HTTPCookieStorage.shared.cookies ?? []).filter {
                cookieDomain($0.domain, matches: host)
            }
        } else {
            cookiesToDelete = HTTPCookieStorage.shared.cookies ?? []
        }

        for cookie in cookiesToDelete {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    internal static func resolvedTestingResetHost(
        baseUrlOverride: String?,
        currentBaseUrl: String,
        appBaseUrl: String
    ) -> String? {
        for candidate in [baseUrlOverride, currentBaseUrl, appBaseUrl] {
            guard let candidate,
                  let host = URL(string: candidate)?.host?.lowercased(),
                  !host.isEmpty,
                  host != "late-init.invalid" else {
                continue
            }
            return host
        }
        return nil
    }

    internal static func shouldRemoveTestingWebsiteDataRecord(named displayName: String, forHost host: String) -> Bool {
        let normalizedDisplayName = displayName.lowercased()
        let normalizedHost = host.lowercased()

        return normalizedDisplayName == normalizedHost ||
               normalizedDisplayName.hasSuffix("." + normalizedHost) ||
               normalizedHost.hasSuffix("." + normalizedDisplayName)
    }

    internal static func testingResetWebsiteDataTypes() -> Set<String> {
        var dataTypes: Set<String> = [
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeWebSQLDatabases,
            WKWebsiteDataTypeOfflineWebApplicationCache,
        ]

        if #available(iOS 11.3, *) {
            dataTypes.insert(WKWebsiteDataTypeFetchCache)
            dataTypes.insert(WKWebsiteDataTypeServiceWorkerRegistrations)
        }

        if #available(iOS 16.0, *) {
            dataTypes.insert(WKWebsiteDataTypeFileSystem)
        }

        return dataTypes
    }
}
