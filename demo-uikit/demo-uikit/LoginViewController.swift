//
//  LoginViewController.swift

import Foundation
import UIKit
import Combine
import FronteggSwift

/// A view controller that handles the login process.
/// This component displays a login form and handles the authentication process.
class LoginViewController: BaseViewController {
    
    /// The error label for the login view
    @IBOutlet weak var errorLabel: UILabel!
    /// The retry button for the login view
    @IBOutlet weak var retryButton: UIButton!
    /// The loader for the login view
    @IBOutlet weak var loader: UIActivityIndicatorView!
    
    private var cancelables =  Set<AnyCancellable>()
    override var prefersStatusBarHidden: Bool {
        return true
    }
    /// The supported interface orientations for the login view
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    /// The view did appear for the login view      
    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "LoginPageRoot"
        errorLabel.accessibilityIdentifier = "LoginErrorLabel"
        retryButton.accessibilityIdentifier = "RetryButton"
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.checkSession()
    }
    
    /// Displays the Frontegg login modal or navigates to the main page based on authentication state.
    private func checkSession(allowAutoLogin: Bool = false) {
        self.hideError()

        if UIKitTestMode.isEnabled && !UIKitTestBootstrapper.shared.isReady {
            return
        }

        if !allowAutoLogin &&
            (UIKitTestMode.shouldPreserveLoggedOutState || UIKitTestMode.isAutoLoginSuppressedAfterExplicitLogout()) {
            self.showLoggedOutState()
            return
        }

        let auth = FronteggApp.shared.auth

        auth.getOrRefreshAccessToken() { [weak self] result in
            Task { @MainActor in
                guard let self else { return }

                switch(result){
                case .success(let accessToken):
                    if(accessToken == nil){
                        print("Not authenticated")
                        let loginHint = UIKitTestMode.isEnabled ? UIKitTestMode.passwordEmail : nil
                        FronteggAuth.shared.login(loginHint: loginHint)
                    } else {
                        print("Authenticated with valid access token")
                        self.handlePostLoginFlow()
                    }
                case .failure(let error):
                    print("Failed to refresh error \(error.localizedDescription)")
                    self.showError(error: error.localizedDescription)
                }
            }
        }
    }
    
    /// Hides the error label, retry button, and loader.
    private func hideError() {
        self.errorLabel.isHidden = true
        self.errorLabel.text = nil
        self.retryButton.isHidden = true
        self.loader.isHidden = false
        self.setRetryButtonTitle("Retry Button")
    }
    
    /// Shows the error label, retry button, and loader.
    private func showError(error: String) {
        self.errorLabel.isHidden = false
        self.retryButton.isHidden = false
        self.loader.isHidden = true
        self.errorLabel.text = error
        self.setRetryButtonTitle("Retry")
    }

    /// Shows an idle logged-out state without auto-starting login again.
    private func showLoggedOutState() {
        self.errorLabel.isHidden = true
        self.errorLabel.text = nil
        self.retryButton.isHidden = false
        self.loader.isHidden = true
        self.setRetryButtonTitle("Log In")
    }

    private func setRetryButtonTitle(_ title: String) {
        if var configuration = self.retryButton.configuration {
            configuration.title = title
            self.retryButton.configuration = configuration
        }
        self.retryButton.setTitle(title, for: .normal)
    }
    
    
    
    @IBAction func retryButtonPressed(_ sender: Any) {
        UIKitTestMode.clearAutoLoginSuppression()
        self.checkSession(allowAutoLogin: true)
    }
    
    /// Handles the post-login navigation flow.
    private func handlePostLoginFlow() {
        navigateToMainPage()
    }
    
    /// Navigates to the main page after successful login.
    private func navigateToMainPage() {
        sceneDelegate?.showAuthenticatedRoot()
    }
    
}
