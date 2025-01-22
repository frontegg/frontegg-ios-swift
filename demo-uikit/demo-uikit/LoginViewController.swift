//
//  LoginViewController.swift

import Foundation
import UIKit
import Combine
import FronteggSwift

class LoginViewController: BaseViewController {
    
    @IBOutlet weak var errorLabel: UILabel!
    @IBOutlet weak var retryButton: UIButton!
    @IBOutlet weak var loader: UIActivityIndicatorView!
    
    private var cancelables =  Set<AnyCancellable>()
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    override func viewDidAppear(_ animated: Bool) {
        self.checkSession()
    }
    
    /// Displays the Frontegg login modal or navigates to the main page based on authentication state.
    private func checkSession() {
        self.hideError()
        let auth = FronteggApp.shared.auth
        
        
        auth.getOrRefreshAccessToken() { result in
            switch(result){
            case .success(let accessToken):
                if(accessToken == nil){
                    print("Not authenticated")
                    FronteggAuth.shared.login()
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
    
    private func hideError() {
        self.errorLabel.isHidden = true
        self.retryButton.isHidden = true
        self.loader.isHidden = false
    }
    private func showError(error: String) {
        self.errorLabel.isHidden = false
        self.retryButton.isHidden = false
        self.loader.isHidden = true
        self.errorLabel.text = error
    }
    
    
    
    @IBAction func retryButtonPressed(_ sender: Any) {
        self.checkSession()
    }
    
    /// Handles the post-login navigation flow.
    private func handlePostLoginFlow() {
        if let _ = sceneDelegate?.window?.rootViewController as? StreamViewController {
            print("User is already on the main page.")
        } else {
            navigateToMainPage()
        }
    }
    
    /// Navigates to the main page after successful login.
    private func navigateToMainPage() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let mainVC = storyboard.instantiateViewController(withIdentifier: "StreamViewController")
        sceneDelegate?.window?.rootViewController = mainVC
    }
    
}



