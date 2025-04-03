//
//  MainNavController.swift
//  demo-uikit
//
//  Created by David Antoon on 08/01/2025.
//
import Foundation
import UIKit

/// A navigation controller for the main view of the demo application.
/// This component handles the navigation between views in the demo application.
class MainNavController: UINavigationController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        guard let topVC = self.topViewController else { return .portrait }
        
        return topVC.supportedInterfaceOrientations
    }
    
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        guard let topVC = self.topViewController else { return .portrait }
        
        return topVC.preferredInterfaceOrientationForPresentation
    }
    
}
