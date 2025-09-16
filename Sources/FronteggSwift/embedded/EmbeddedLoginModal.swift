//
//  EmbeddedLoginModal.swift
//  
//
//  Created by David Frontegg on 15/09/2023.
//

import Foundation
import SwiftUI


class VCHolder :ObservableObject  {
    var vc: UIViewController?
    
    public static let shared = VCHolder()
}

public struct EmbeddedLoginModal: View {
    @StateObject var fronteggAuth = FronteggApp.shared.auth
    
    public init(parentVC: UIViewController? = nil) {
        VCHolder.shared.vc = parentVC
    }
    
    public var body: some View {
        ZStack {
            if(fronteggAuth.initializing || fronteggAuth.showLoader) {
                DefaultLoader()
            } else if !fronteggAuth.initializing
                && !fronteggAuth.showLoader
                && fronteggAuth.isAuthenticated
                && !fronteggAuth.isStepUpAuthorization
            {

                DefaultLoader().onAppear() {
                    VCHolder.shared.vc?.presentedViewController?.dismiss(animated: true)
                    VCHolder.shared.vc = nil
                }
            } else {
                EmbeddedLoginPage()
            }
            
        }.onAppear {
            self.fronteggAuth.webLoading = true
        }
        .onDisappear {
            self.fronteggAuth.webLoading = false
        }
        .environmentObject(fronteggAuth)
    }
}

struct EmbeddedLoginModal_Previews: PreviewProvider {
    static var previews: some View {
        EmbeddedLoginModal()
    }
}

