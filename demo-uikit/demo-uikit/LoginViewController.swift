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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    override func viewDidAppear(_ animated: Bool) {
        displayFronteggLogin()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    /// Displays the Frontegg login modal or navigates to the main page based on authentication state.
    private func displayFronteggLogin() {
        
        let auth = FronteggApp.shared.auth
        
        
        if(!auth.isLoading && !auth.refreshingToken && !auth.initializing){
            self.onStateChange(auth.isLoading, auth.refreshingToken, auth.initializing)
        }else {
            cancelables.insert(auth.$isLoading.combineLatest(auth.$refreshingToken, auth.$initializing).sink(receiveValue: self.onStateChange))
        }
        
    }
    
    private func onStateChange(_ isLoading: Bool, _ refreshingToken: Bool, _ initializing: Bool){
        if(!isLoading && !refreshingToken && !initializing){
            removeObservables()
            if !FronteggAuth.shared.isAuthenticated {
                FronteggAuth.shared.login()
            } else {
                self.handlePostLoginFlow()
            }
        }
    }
    
    
    func removeObservables(){
        cancelables.forEach { cancelable in
            cancelable.cancel()
        }
        cancelables.removeAll()
    }
    override func viewWillDisappear(_ animated: Bool) {
        removeObservables()
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



