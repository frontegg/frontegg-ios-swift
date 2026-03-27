import Foundation
import FronteggSwift

enum UIKitTestMode {
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
final class UIKitTestBootstrapper {
    static let shared = UIKitTestBootstrapper()

    func bootstrapIfNeeded() async {
        guard UIKitTestMode.isEnabled else { return }

        guard let baseUrl = UIKitTestMode.baseUrl,
              let clientId = UIKitTestMode.clientId else {
            assertionFailure("Missing E2E launch environment for demo-uikit")
            return
        }

        if UIKitTestMode.shouldResetState {
#if DEBUG
            await FronteggApp.shared.resetForTesting(baseUrlOverride: baseUrl)
#endif
        }

        FronteggApp.shared.manualInit(
            baseUrl: baseUrl,
            cliendId: clientId,
            handleLoginWithSocialLogin: true,
            handleLoginWithSSO: true,
            entitlementsEnabled: false
        )
    }
}
