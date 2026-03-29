//
//  Constants.swift

import Foundation
import UIKit

/// A class that contains constants for the demo application.
class Constants {
    /// Resets the application to the login screen.
    static func resetToLogin(){
        Task { @MainActor in
            sceneDelegate?.showUnauthenticatedRoot()
        }
    }
    
    
}

let PLAY_MAX_RETRY: Int = 5
