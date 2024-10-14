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
    private let loginHint: String?
    
    public init(parentVC: UIViewController? = nil, loginHint:String? = nil) {
        VCHolder.shared.vc = parentVC
        self.loginHint = loginHint
    }
    
    
    
    public var body: some View {
        ZStack {
            if(fronteggAuth.initializing || fronteggAuth.showLoader) {
                DefaultLoader()
            } else if !fronteggAuth.initializing
                && !fronteggAuth.showLoader
                && fronteggAuth.isAuthenticated {

                DefaultLoader().onAppear() {
                    
                    VCHolder.shared.vc?.presentedViewController?.dismiss(animated: true)
                    VCHolder.shared.vc = nil
                }
            } else {
                EmbeddedLoginPage(loginHint: loginHint)
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

