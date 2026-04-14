//
//  AutoLoginTestMode.swift
//  demo-auto-login
//

import Foundation
import SwiftUI
import Combine
import FronteggSwift

enum AutoLoginTestMode {
    static let enabledEnv = "frontegg-testing"
    static let baseUrlEnv = "FRONTEGG_E2E_BASE_URL"
    static let clientIdEnv = "FRONTEGG_E2E_CLIENT_ID"
    static let resetStateEnv = "FRONTEGG_E2E_RESET_STATE"
    static let forceNetworkPathOfflineEnv = "FRONTEGG_E2E_FORCE_NETWORK_PATH_OFFLINE"
    static let enableOfflineModeEnv = "FRONTEGG_E2E_ENABLE_OFFLINE_MODE"
    static let embeddedPasswordEmail = "test@frontegg.com"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[enabledEnv] == "true"
    }

    static var baseUrl: String? {
        ProcessInfo.processInfo.environment[baseUrlEnv]
    }

    static var clientId: String? {
        ProcessInfo.processInfo.environment[clientIdEnv]
    }

    static var shouldResetState: Bool {
        ProcessInfo.processInfo.environment[resetStateEnv] == "1"
    }

    static var forcesNetworkPathOffline: Bool {
        ProcessInfo.processInfo.environment[forceNetworkPathOfflineEnv] == "1"
    }

    static var enableOfflineModeOverride: Bool? {
        switch ProcessInfo.processInfo.environment[enableOfflineModeEnv] {
        case "1": return true
        case "0": return false
        default:  return nil
        }
    }
}

@MainActor
final class AutoLoginUITestDiagnostics: ObservableObject {
    static let shared = AutoLoginUITestDiagnostics()

    private static let noConnectionSeenKey = "demo-auto-login.e2e.noConnectionSeenEver"

    @Published private(set) var noConnectionPageSeenEver: Bool

    private init() {
        noConnectionPageSeenEver = UserDefaults.standard.bool(forKey: Self.noConnectionSeenKey)
    }

    func resetPersistentState() {
        UserDefaults.standard.removeObject(forKey: Self.noConnectionSeenKey)
        noConnectionPageSeenEver = false
    }

    func markNoConnectionPageSeen() {
        guard !noConnectionPageSeenEver else { return }
        noConnectionPageSeenEver = true
        UserDefaults.standard.set(true, forKey: Self.noConnectionSeenKey)
    }
}

@MainActor
final class AutoLoginBootstrapper: ObservableObject {
    @Published private(set) var isReady = false

    init() {
        if AutoLoginTestMode.isEnabled {
            Task { @MainActor in
                await bootstrapForTesting()
            }
        } else {
            isReady = true
        }
    }

    private func bootstrapForTesting() async {
        guard let baseUrl = AutoLoginTestMode.baseUrl,
              let clientId = AutoLoginTestMode.clientId else {
            assertionFailure("Missing E2E launch environment for demo-auto-login")
            isReady = true
            return
        }

        if AutoLoginTestMode.shouldResetState {
#if DEBUG
            await FronteggApp.shared.resetForTesting(baseUrlOverride: baseUrl)
#endif
            AutoLoginUITestDiagnostics.shared.resetPersistentState()
        }

#if DEBUG
        FronteggApp.shared.configureTestingNetworkPathAvailability(
            AutoLoginTestMode.forcesNetworkPathOffline ? false : nil
        )
#endif

#if DEBUG
        if let offlineModeOverride = AutoLoginTestMode.enableOfflineModeOverride {
            FronteggApp.shared.configureTestingOfflineMode(offlineModeOverride)
        }
#endif

        FronteggApp.shared.shouldPromptSocialLoginConsent = false
        FronteggApp.shared.manualInit(
            baseUrl: baseUrl,
            cliendId: clientId,
            handleLoginWithSocialLogin: true,
            handleLoginWithSSO: true,
            handleLoginWithCustomSSO: true,
            handleLoginWithCustomSocialLoginProvider: true,
            handleLoginWithSocialProvider: true,
            entitlementsEnabled: false
        )
        isReady = true
    }
}
