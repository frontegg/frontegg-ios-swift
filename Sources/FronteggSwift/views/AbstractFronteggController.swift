//
//  AbstractFronteggController.swift
//
//
//  Created by David Frontegg on 30/12/2022.
//

import Foundation
import UIKit
import SwiftUI


open class AbstractFronteggController: UIViewController {
    private var logger = getLogger("AbstractFronteggController")
    
    open func navigateToAuthenticated() {
        logger.error("Missing AbstractFronteggController implementation class")
        fatalError("Not implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        logger.trace("viewDidLoad()")
        let childView = UIHostingController(rootView: FronteggUIKitWrapper(
            navigateToAuthenticated: navigateToAuthenticated,
            loaderView: nil
        ))
        addChild(childView)
        childView.view.frame = self.view.bounds
        self.view.addSubview(childView.view)
        childView.didMove(toParent: self)
    }


}
