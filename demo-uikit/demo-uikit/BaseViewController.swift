//
//  BaseViewController.swift

import UIKit
import Foundation
import FronteggSwift

/// A base view controller for the demo application.    
/// This component provides common functionality for all view controllers in the demo application.
class BaseViewController: UIViewController {
    
    /// The app delegate for the demo application
    var appDelegate: AppDelegate {
        get { UIApplication.shared.delegate as! AppDelegate }
    }
    
    // MARK: - Screen interface rotation on iOS 15.x. But iOS 12.x, 13.x, 16.x
    override var shouldAutorotate: Bool {
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .portrait
    }
    
    // MARK: - Lifecycle Methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        appDelegate.currentVC = self
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    
}
