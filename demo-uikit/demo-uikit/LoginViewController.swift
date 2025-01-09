//
//  LoginViewController.swift

import Foundation
import UIKit
import Combine
import FronteggSwift

class LoginViewController: BaseViewController {
    
       override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupObservers()
        displayFronteggLogin()
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
      return .portrait
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
        
    /// Displays the Frontegg login modal or navigates to the main page based on authentication state.
    private func displayFronteggLogin() {
        let subscriber = AnySubscriber<Bool, Never>(
            receiveSubscription: { query in
                query.request(.unlimited)
            },
            receiveValue: { [weak self] showLoader in
                guard let self = self else { return .none }
                if !showLoader {
//                    MBProgressHUD.hide(for: self.view, animated: false)
                    if !FronteggApp.shared.auth.isAuthenticated {
                        FronteggApp.shared.auth.login()
                        return .none
                    } else {
                        self.handlePostLoginFlow()
                    }
                } else {
//                    MBProgressHUD.showAdded(to: self.view, animated: false)
                }
                return .none
            }
        )
        FronteggApp.shared.auth.$showLoader.subscribe(subscriber)
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

    /// Refreshes the token if it is close to expiration.
    private func refreshTokenIfNeeded() {
        Task {
            let refreshed = await FronteggApp.shared.auth.refreshTokenIfNeeded()
            if refreshed {
                print("Token refreshed successfully.")
            } else {
                print("Token not refreshed, possibly still valid.")
            }
        }
    }

    /// Sets up observers for app lifecycle events to trigger token refresh.
    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    /// Called when the app becomes active; triggers token refresh.
    @objc private func appDidBecomeActive() {
        print(#function)
    }
    
    
    private func getPresentedTopViewController() -> UIViewController?{
        let keyWindow = UIApplication.shared.windows.filter {$0.isKeyWindow}.first

        if var topController = keyWindow?.rootViewController {
            while let presentedViewController = topController.presentedViewController {
                topController = presentedViewController
                return topController
                
            }

        }
        return nil
    }
   
}



