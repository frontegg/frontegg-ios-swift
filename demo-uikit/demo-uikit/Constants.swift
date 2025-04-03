//
//  Constants.swift

import Foundation
import UIKit

/// A class that contains constants for the demo application.
class Constants {
    /// Resets the application to the login screen.
    static func resetToLogin(){
        let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        if let delegate = windowScene?.delegate as? SceneDelegate, let window = delegate.window{
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let vc = storyboard.instantiateViewController(withIdentifier: "LoginViewController")
            let navigation = UINavigationController(rootViewController: vc)
            window.rootViewController = navigation
        }
    }
    
    
}

let PLAY_MAX_RETRY: Int = 5
