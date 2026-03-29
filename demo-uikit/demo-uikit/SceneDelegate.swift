//
//  SceneDelegate.swift
//  demo-uikit
//
//  Created by David Antoon on 29/01/2024.
//

import UIKit
import FronteggSwift

/// A scene delegate for the demo application.
/// This component handles the scene delegate for the demo application.
@MainActor
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    private enum RootDestination: Equatable {
        case bootstrapLoading
        case bootstrapError(String)
        case login
        case stream
        case authenticationCallback
    }
    
    let fronteggAuth = FronteggAuth.shared
    var window: UIWindow?
    private var bootstrapObserver: NSObjectProtocol?
    private var currentRootDestination: RootDestination?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        self.window = window
        currentRootDestination = nil
        observeBootstrapStateIfNeeded()
        updateRootForCurrentState()
        window.makeKeyAndVisible()
    }
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        handleIncomingAuthURL(url)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard let url = userActivity.webpageURL else { return }
        handleIncomingAuthURL(url)
    }
    
    func sceneDidDisconnect(_ scene: UIScene) {
        currentRootDestination = nil
        removeBootstrapObserver()
    }
    
    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
    }
    
    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }
    
    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }
    
    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
    }

    func showAuthenticatedRoot() {
        setRootDestination(.stream)
    }

    func showUnauthenticatedRoot() {
        setRootDestination(.login)
    }

    private func observeBootstrapStateIfNeeded() {
        guard bootstrapObserver == nil else { return }

        bootstrapObserver = NotificationCenter.default.addObserver(
            forName: UIKitTestBootstrapper.stateDidChangeNotification,
            object: UIKitTestBootstrapper.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateRootForCurrentState()
            }
        }
    }

    private func removeBootstrapObserver() {
        guard let bootstrapObserver else { return }
        NotificationCenter.default.removeObserver(bootstrapObserver)
        self.bootstrapObserver = nil
    }

    private func updateRootForCurrentState() {
        guard window != nil else { return }

        if UIKitTestMode.isEnabled {
            switch UIKitTestBootstrapper.shared.state {
            case .idle, .bootstrapping:
                setRootDestination(.bootstrapLoading)
                UIKitTestBootstrapper.shared.bootstrapIfNeeded()
            case .failed(let message):
                setRootDestination(.bootstrapError(message))
            case .ready:
                showCurrentAuthenticationRoot()
            }
            return
        }

        showCurrentAuthenticationRoot()
    }

    private func showCurrentAuthenticationRoot() {
        if fronteggAuth.isAuthenticated {
            showAuthenticatedRoot()
        } else {
            showUnauthenticatedRoot()
        }
    }

    private func showAuthenticationCallbackBridge() {
        setRootDestination(.authenticationCallback)
    }

    private func handleIncomingAuthURL(_ url: URL) {
        guard FronteggApp.shared.auth.handleOpenUrl(url) else { return }
        showAuthenticationCallbackBridge()
    }

    private func setRootDestination(_ destination: RootDestination) {
        guard currentRootDestination != destination else { return }

        currentRootDestination = destination
        window?.rootViewController = makeRootViewController(for: destination)
        window?.makeKeyAndVisible()
    }

    private func makeRootViewController(for destination: RootDestination) -> UIViewController {
        switch destination {
        case .bootstrapLoading:
            return UIKitBootstrapViewController(
                message: "Preparing demo...",
                showsActivityIndicator: true
            )
        case .bootstrapError(let message):
            return UIKitBootstrapViewController(
                message: message,
                showsActivityIndicator: false
            )
        case .login:
            return makeNavigationRoot(storyboardIdentifier: "LoginViewController")
        case .stream:
            return makeNavigationRoot(storyboardIdentifier: "StreamViewController")
        case .authenticationCallback:
            return AuthenticationController()
        }
    }

    private func makeNavigationRoot(storyboardIdentifier: String) -> UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let rootViewController = storyboard.instantiateViewController(withIdentifier: storyboardIdentifier)
        let navigationController = MainNavController(rootViewController: rootViewController)
        navigationController.setNavigationBarHidden(true, animated: false)
        return navigationController
    }
}

private final class UIKitBootstrapViewController: UIViewController {
    private let message: String
    private let showsActivityIndicator: Bool

    init(message: String, showsActivityIndicator: Bool) {
        self.message = message
        self.showsActivityIndicator = showsActivityIndicator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = showsActivityIndicator
            ? "BootstrapLoaderView"
            : "BootstrapErrorView"

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false

        if showsActivityIndicator {
            let activityIndicator = UIActivityIndicatorView(style: .large)
            activityIndicator.startAnimating()
            activityIndicator.accessibilityIdentifier = "BootstrapActivityIndicator"
            stackView.addArrangedSubview(activityIndicator)
        }

        let label = UILabel()
        label.text = message
        label.numberOfLines = 0
        label.textAlignment = .center
        label.accessibilityIdentifier = "BootstrapMessageLabel"
        stackView.addArrangedSubview(label)

        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor),
        ])
    }
}
