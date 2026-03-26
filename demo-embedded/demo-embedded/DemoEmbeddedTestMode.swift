import Foundation
import SwiftUI
import FronteggSwift

enum DemoEmbeddedTestMode {
    static let enabledEnv = "frontegg-testing"
    static let baseUrlEnv = "FRONTEGG_E2E_BASE_URL"
    static let clientIdEnv = "FRONTEGG_E2E_CLIENT_ID"
    static let resetStateEnv = "FRONTEGG_E2E_RESET_STATE"
    static let forceNetworkPathOfflineEnv = "FRONTEGG_E2E_FORCE_NETWORK_PATH_OFFLINE"
    static let requestAuthorizeRefreshToken = "signup-refresh-token"
    static let embeddedPasswordEmail = "test@frontegg.com"
    static let embeddedSAMLEmail = "test@saml-domain.com"
    static let embeddedOIDCEmail = "test@oidc-domain.com"

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

    static var customSSOUrl: String? {
        guard let baseUrl else { return nil }
        return "\(baseUrl)/idp/custom-sso"
    }

    static var directSocialLoginUrl: String? {
        guard let baseUrl else { return nil }
        return "\(baseUrl)/idp/social/mock-social-provider"
    }
}

@MainActor
final class DemoEmbeddedUITestDiagnostics: ObservableObject {
    static let shared = DemoEmbeddedUITestDiagnostics()

    private static let noConnectionSeenKey = "demo-embedded.e2e.noConnectionSeenEver"

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
final class DemoEmbeddedBootstrapper: ObservableObject {
    @Published private(set) var isReady = false

    init() {
        if DemoEmbeddedTestMode.isEnabled {
            Task { @MainActor in
                await bootstrapForTesting()
            }
        } else {
            isReady = true
        }
    }

    private func bootstrapForTesting() async {
        guard let baseUrl = DemoEmbeddedTestMode.baseUrl,
              let clientId = DemoEmbeddedTestMode.clientId else {
            assertionFailure("Missing E2E launch environment for demo-embedded")
            isReady = true
            return
        }

        if DemoEmbeddedTestMode.shouldResetState {
            await FronteggApp.shared.resetForTesting(baseUrlOverride: baseUrl)
            DemoEmbeddedUITestDiagnostics.shared.resetPersistentState()
        }

#if DEBUG
        FronteggApp.shared.configureTestingNetworkPathAvailability(
            DemoEmbeddedTestMode.forcesNetworkPathOffline ? false : nil
        )
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
