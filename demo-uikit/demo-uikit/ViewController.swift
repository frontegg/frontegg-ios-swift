//
//  ViewController.swift
//  demo-uikit
//
//  Created by David Antoon on 29/01/2024.
//

import UIKit
import FronteggSwift

class ViewController: UIViewController {
    @IBOutlet weak var label: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        let fronteggAuth = FronteggApp.shared.auth
        label.text = fronteggAuth.user?.email
    }

    
    @IBAction func logoutButton (){
        FronteggApp.shared.auth.logout() { _ in
            self.view.window?.rootViewController = AuthenticationController()
            self.view.window?.makeKeyAndVisible()
        }
  }

}

