//
//  Constants.swift

import Foundation
import UIKit

class Constants {
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
