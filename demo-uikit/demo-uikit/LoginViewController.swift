//
//  LoginViewController.swift

import Foundation
import UIKit
import Combine
import FronteggSwift

class LoginViewController: BaseViewController {
    
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
        
        let auth = FronteggApp.shared.auth
        
        
        auth.getOrRefreshAccessToken() { result in
            switch(result){
            case .success(let accessToken):
                if(accessToken == nil){
                    print("Not authenticated")
                    FronteggAuth.shared.login()
                } else {
                    self.handlePostLoginFlow()
                }
            case .failure(let error):
                print("Failed to refresh error \(error.localizedDescription)")
                self.handlePostLoginFlow()
                // maybe displaying error with retry button
            }
        }
        
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



