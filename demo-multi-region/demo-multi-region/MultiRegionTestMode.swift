import Foundation
import FronteggSwift

enum MultiRegionTestMode {
    static let enabledEnv = "frontegg-testing"
    static let baseUrlEnv = "FRONTEGG_E2E_BASE_URL"
    static let clientIdEnv = "FRONTEGG_E2E_CLIENT_ID"
    static let resetStateEnv = "FRONTEGG_E2E_RESET_STATE"
    static let passwordEmail = "test@frontegg.com"

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
}

@MainActor
final class MultiRegionBootstrapper: ObservableObject {
    @Published private(set) var isReady = false

    init() {
        if MultiRegionTestMode.isEnabled {
            Task { @MainActor in
                await bootstrapForTesting()
            }
        } else {
            isReady = true
        }
    }

    private func bootstrapForTesting() async {
        guard let baseUrl = MultiRegionTestMode.baseUrl,
              let clientId = MultiRegionTestMode.clientId else {
            assertionFailure("Missing E2E launch environment for demo-multi-region")
            isReady = true
            return
        }

        if MultiRegionTestMode.shouldResetState {
#if DEBUG
            await FronteggApp.shared.resetForTesting(baseUrlOverride: baseUrl)
#endif
        }

        FronteggApp.shared.manualInit(
            baseUrl: baseUrl,
            cliendId: clientId,
            handleLoginWithSocialLogin: true,
            handleLoginWithSSO: true,
            entitlementsEnabled: true
        )
        isReady = true
    }
}
