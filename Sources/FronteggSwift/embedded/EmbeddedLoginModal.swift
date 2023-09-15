//
//  EmbeddedLoginModal.swift
//  
//
//  Created by David Frontegg on 15/09/2023.
//

import Foundation
import SwiftUI


public struct EmbeddedLoginModal: View {
    @StateObject var fronteggAuth = FronteggApp.shared.auth
    public var parentVC: UIViewController? = nil
    
    
    init(parentVC: UIViewController? = nil) {
        self.parentVC = parentVC
    }
    
    
    public var body: some View {
        ZStack {
            if(fronteggAuth.initializing || fronteggAuth.showLoader) {
                DefaultLoader()
            } else if !fronteggAuth.initializing
                && !fronteggAuth.showLoader
                && fronteggAuth.isAuthenticated {
                
                DefaultLoader().onAppear() {
                    parentVC?.presentedViewController?.dismiss(animated: true)
                }
            } else {
                EmbeddedLoginPage()
            }
            
        }
        .environmentObject(fronteggAuth)
    }
}

struct EmbeddedLoginModal_Previews: PreviewProvider {
    static var previews: some View {
        EmbeddedLoginModal()
    }
}

