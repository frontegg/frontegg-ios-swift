import Foundation
import FronteggSwift

enum UIKitTestMode {
    static let enabledEnv = "frontegg-testing"
    static let baseUrlEnv = "FRONTEGG_E2E_BASE_URL"
    static let clientIdEnv = "FRONTEGG_E2E_CLIENT_ID"
    static let resetStateEnv = "FRONTEGG_E2E_RESET_STATE"
    static let passwordEmail = "test@frontegg.com"
    @MainActor private static var suppressAutoLoginAfterExplicitLogout = false

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

    @MainActor
    static func suppressNextAutoLoginAfterExplicitLogout() {
        guard isEnabled else { return }
        suppressAutoLoginAfterExplicitLogout = true
    }

    @MainActor
    static func consumeAutoLoginSuppressionIfNeeded() -> Bool {
        guard isEnabled, suppressAutoLoginAfterExplicitLogout else { return false }
        suppressAutoLoginAfterExplicitLogout = false
        return true
    }

    @MainActor
    static func resetAutoLoginSuppression() {
        suppressAutoLoginAfterExplicitLogout = false
    }
}

enum UIKitTestBootstrapState: Equatable {
    case idle
    case bootstrapping
    case ready
    case failed(String)
}

@MainActor
final class UIKitTestBootstrapper {
    static let shared = UIKitTestBootstrapper()
    nonisolated static let stateDidChangeNotification = Notification.Name("UIKitTestBootstrapperStateDidChange")

    private(set) var state: UIKitTestBootstrapState = UIKitTestMode.isEnabled ? .idle : .ready {
        didSet {
            guard oldValue != state else { return }
            NotificationCenter.default.post(name: Self.stateDidChangeNotification, object: self)
        }
    }

    private var bootstrapTask: Task<Void, Never>?

    var isReady: Bool {
        if case .ready = state {
            return true
        }
        return false
    }

    func bootstrapIfNeeded() {
        guard UIKitTestMode.isEnabled else {
            state = .ready
            return
        }

        switch state {
        case .bootstrapping, .ready:
            return
        case .idle, .failed:
            break
        }

        state = .bootstrapping
        bootstrapTask?.cancel()
        bootstrapTask = Task { @MainActor in
            await self.bootstrapForTesting()
            self.bootstrapTask = nil
        }
    }

    private func bootstrapForTesting() async {
        guard let baseUrl = UIKitTestMode.baseUrl,
              let clientId = UIKitTestMode.clientId else {
            let message = "Missing E2E launch environment for demo-uikit"
            assertionFailure(message)
            state = .failed(message)
            return
        }

        UIKitTestMode.resetAutoLoginSuppression()

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
        state = .ready
    }
}
