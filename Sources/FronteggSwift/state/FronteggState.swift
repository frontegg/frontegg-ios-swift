import Foundation
import Combine


public class FronteggState: ObservableObject {

    // MARK: - Published state (write internally, read publicly)
    
    @Published public private(set) var accessToken: String? = nil
    @Published public private(set) var refreshToken: String? = nil
    @Published public private(set) var user: User? = nil
    @Published public private(set) var isAuthenticated = false
    @Published public private(set) var isStepUpAuthorization = false
    @Published public private(set) var isLoading = true
    @Published public private(set) var webLoading = true
    @Published public private(set) var loginBoxLoading = false
    @Published public private(set) var initializing = true
    @Published public private(set) var lateInit = false
    @Published public private(set) var showLoader = true
    @Published public private(set) var appLink: Bool = false
    @Published public private(set) var externalLink: Bool = false
    @Published public private(set) var selectedRegion: RegionConfig? = nil
    @Published public private(set) var refreshingToken: Bool = false

    public init() {}

    // MARK: - Guarded setters

    /// Sets a value on a KeyPath if the new value is different from the current one.
    /// This overload is for NON-OPTIONAL properties.
    private func setIfChanged<T: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<FronteggState, T>,
        _ newValue: T
    ) {
        if self[keyPath: keyPath] != newValue {
            // Updating non-optional because value changed.")
            self[keyPath: keyPath] = newValue
        }
    }

    /// An overloaded version of `setIfChanged` specifically for OPTIONAL properties.
    /// The KeyPath signature `T?` makes this distinct from the non-optional version.
    private func setIfChanged<T: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<FronteggState, T?>,
        _ newValue: T?
    ) {
        if self[keyPath: keyPath] != newValue {
            // Updating optional because value changed.")
            self[keyPath: keyPath] = newValue
        }
    }

    // MARK: - Public typed setters

    public func setAccessToken(_ v: String?) { setIfChanged(\.accessToken, v) }
    public func setRefreshToken(_ v: String?) { setIfChanged(\.refreshToken, v) }
    public func setUser(_ v: User?) { setIfChanged(\.user, v) }
    public func setIsAuthenticated(_ v: Bool) { setIfChanged(\.isAuthenticated, v) }
    public func setIsStepUpAuthorization(_ v: Bool) { setIfChanged(\.isStepUpAuthorization, v) }
    public func setIsLoading(_ v: Bool) { setIfChanged(\.isLoading, v) }
    public func setWebLoading(_ v: Bool) { setIfChanged(\.webLoading, v) }
    public func setLoginBoxLoading(_ v: Bool) { setIfChanged(\.loginBoxLoading, v) }
    public func setInitializing(_ v: Bool) { setIfChanged(\.initializing, v) }
    public func setLateInit(_ v: Bool) { setIfChanged(\.lateInit, v) }
    public func setShowLoader(_ v: Bool) { setIfChanged(\.showLoader, v) }
    public func setAppLink(_ v: Bool) { setIfChanged(\.appLink, v) }
    public func setExternalLink(_ v: Bool) { setIfChanged(\.externalLink, v) }
    public func setSelectedRegion(_ v: RegionConfig?) { setIfChanged(\.selectedRegion, v) }
    
    public func setRefreshingToken(_ v: Bool) {
        if Thread.isMainThread {
            setIfChanged(\.refreshingToken, v)
        } else {
            DispatchQueue.main.async {
                self.setIfChanged(\.refreshingToken, v)
            }
        }
    }
}
