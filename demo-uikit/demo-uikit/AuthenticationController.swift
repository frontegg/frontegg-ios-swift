//
//  AuthenticationController.swift
//

import UIKit
import FronteggSwift

/// A controller that handles authentication.
/// This component is responsible for navigating to the authenticated screen when the user is authenticated.
class AuthenticationController: AbstractFronteggController {
    
    override func navigateToAuthenticated(){
        sceneDelegate?.showAuthenticatedRoot()
    }
    
}
