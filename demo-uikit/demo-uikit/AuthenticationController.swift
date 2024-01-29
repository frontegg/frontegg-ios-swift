//
//  AuthenticationController.swift
//

import UIKit
import FronteggSwift

class AuthenticationController: AbstractFronteggController {
    
    override func navigateToAuthenticated(){
        // This function will be called when the user is authenticated
        // to navigate your application to the authenticated screen
        
        let mainStoryboard: UIStoryboard = UIStoryboard(name: "Main", bundle: nil)
        let viewController = mainStoryboard.instantiateViewController(withIdentifier: "authenticatedScreen")
        self.view.window?.rootViewController = viewController
        self.view.window?.makeKeyAndVisible()
    }
    
}
