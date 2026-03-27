//
//  FronteggAuth.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import Foundation
import Dispatch
import WebKit
import Combine
import AuthenticationServices
import UIKit
import SwiftUI
import Network



public class FronteggAuth: FronteggState {
    
#if DEBUG
    static var testNetworkPathAvailabilityOverride: Bool? = nil
#endif

    public var embeddedMode: Bool
    public var isRegional: Bool
    public var regionData: [RegionConfig]
    public var baseUrl: String
    public var clientId: String
    public var applicationId: String? = nil
    public var pendingAppLink: URL? = nil
    public var loginHint: String? = nil
    public var lastAttemptReason: AttemptReasonType? = nil
    var activeEmbeddedOAuthFlow: FronteggOAuthFlow = .login
    
    
    weak var webview: CustomWebView? = nil
    
    
    
    public static var shared: FronteggAuth {
        return FronteggApp.shared.auth
    }
    
    let logger = getLogger("FronteggAuth")
    public let credentialManager: CredentialManager
    // internal for extension access (FronteggAuth+AdvancedAuth.swift)
    var multiFactorAuthenticator: MultiFactorAuthenticator
    var stepUpAuthenticator: StepUpAuthenticator
    public var api: Api
    public var featureFlags: FeatureFlags
    public var entitlements: Entitlements
    var subscribers = Set<AnyCancellable>()
    // internal for extension access (Refresh, Testing, Connectivity)
    var refreshTokenDispatch: DispatchWorkItem?
    var offlineDebounceWork: DispatchWorkItem?
    // internal for extension access (FronteggAuth+Connectivity.swift)
    let offlineDebounceDelay: TimeInterval = 0.6
    let unauthenticatedStartupOfflineCommitWindow: TimeInterval = 4.5
    let unauthenticatedStartupProbeDelay: TimeInterval = 0.5
    let unauthenticatedStartupProbeTimeout: TimeInterval = 1.0
    var loginCompletion: CompletionHandler? = nil
    // internal for extension access (Connectivity, Testing, SessionRestore)
    var networkMonitoringToken: NetworkStatusMonitor.OnChangeToken?
    // internal for extension access (FronteggAuth+OAuthErrors.swift)
    var pendingOAuthErrorContext: FronteggOAuthErrorContext?
    var pendingOAuthErrorPresentationWorkItem: DispatchWorkItem?
    var pendingEmbeddedOAuthErrorFallbackWorkItem: DispatchWorkItem?
    let oauthErrorPresentationDelay: TimeInterval = 0.35
    let embeddedOAuthErrorRecoveryFallbackDelay: TimeInterval = 1.25
    // internal for extension access (SessionRestore, Testing, Refresh, HostedFlows)
    var isInitializingWithTokens: Bool = false
    @MainActor var isLoginInProgress: Bool = false
    // internal for extension access (FronteggAuth+Entitlements.swift)
    let entitlementsLoadLock = NSLock()
    var entitlementsLoadInProgress: Bool = false
    var entitlementsLoadPendingCompletions: [((Bool) -> Void)] = []
    var entitlementsLoadForceRefreshPending: Bool = false

    internal static func isUserCancelledOAuthFlow(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == ASWebAuthenticationSessionError.errorDomain,
           nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
            return true
        }

        if let authError = error as? ASAuthorizationError,
           authError.code == .canceled {
            return true
        }

        return false
    }
    
    init (
        baseUrl:String,
        clientId: String,
        applicationId: String?,
        credentialManager: CredentialManager,
        isRegional: Bool,
        regionData: [RegionConfig],
        embeddedMode: Bool,
        isLateInit: Bool? = false,
        entitlementsEnabled: Bool = false
    ) {
        self.isRegional = isRegional
        self.regionData = regionData
        self.credentialManager = credentialManager

        self.embeddedMode = embeddedMode
        self.baseUrl = baseUrl
        self.clientId = clientId
        self.applicationId = applicationId
        self.api = Api(baseUrl: self.baseUrl, clientId: self.clientId, applicationId: self.applicationId)
        self.featureFlags = FeatureFlags(.init(clientId: self.clientId, api: self.api))
        self.entitlements = Entitlements(.init(api: self.api, enabled: entitlementsEnabled))
        self.multiFactorAuthenticator = MultiFactorAuthenticator(api: api, baseUrl: baseUrl)
        self.stepUpAuthenticator = StepUpAuthenticator(credentialManager: credentialManager)
        
        super.init()
        setLateInit(isLateInit ?? false)
        setSelectedRegion(self.getSelectedRegion())
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        if ( isRegional || isLateInit == true ) {
            setInitializing(false)
            setShowLoader(false)
            return;
        }
        
        
        self.initializeSubscriptions()
    }
    
    
    deinit {
        // Remove the observer when the instance is deallocated
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
    
    // MARK: Region Management — see FronteggAuth+RegionManagement.swift
    // MARK: Entitlements — see FronteggAuth+Entitlements.swift
    // MARK: Session Restore — see FronteggAuth+SessionRestore.swift
    // MARK: Credential Hydration — see FronteggAuth+CredentialHydration.swift
    // MARK: Refresh — see FronteggAuth+Refresh.swift
    // MARK: OAuth Callbacks — see FronteggAuth+OAuthCallbacks.swift
    // MARK: Hosted Flows — see FronteggAuth+HostedFlows.swift
    // MARK: Social Flows — see FronteggAuth+SocialFlows.swift
    // MARK: Embedded & DeepLink — see FronteggAuth+EmbeddedAndDeepLink.swift
    // MARK: Advanced Auth — see FronteggAuth+AdvancedAuth.swift

}
