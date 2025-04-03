//
//  ViewController.swift
//  demo-uikit
//
//  Created by David Antoon on 29/01/2024.
//

import UIKit
import FronteggSwift

/// A view controller that displays the user's profile information.
/// This component handles the user's profile information and allows them to logout.
class ViewController: UIViewController {
    /// The label for the user's email
    @IBOutlet weak var label: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        let fronteggAuth = FronteggApp.shared.auth
        label.text = fronteggAuth.user?.email
    }
    
    /// Logs out the user and navigates to the login screen.
    @IBAction func logoutButton (){
        FronteggApp.shared.auth.logout() { _ in
            self.view.window?.rootViewController = AuthenticationController()
            self.view.window?.makeKeyAndVisible()
        }
    }
    
}

