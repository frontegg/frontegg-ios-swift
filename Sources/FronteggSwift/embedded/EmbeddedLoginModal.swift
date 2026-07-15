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
            FronteggRuntime.testingLog(
                "E2E EmbeddedLoginModal onAppear initializing=\(fronteggAuth.initializing) showLoader=\(fronteggAuth.showLoader) isAuthenticated=\(fronteggAuth.isAuthenticated) isLoading=\(fronteggAuth.isLoading)"
            )
            self.fronteggAuth.setWebLoading(true)
        }
        .onDisappear {
            self.fronteggAuth.setWebLoading(false)
            // The modal can be dismissed without the login flow completing
            // (a cancelled passkey sheet aborting the ceremony, swipe-down,
            // host-app dismissal). A pending loginCompletion left un-fired
            // permanently blocks every subsequent login() call - resolve it
            // as canceled so the next attempt starts fresh.
            if !self.fronteggAuth.isAuthenticated {
                self.fronteggAuth.loginCompletion?(.failure(FronteggError.authError(.operationCanceled)))
                self.fronteggAuth.loginCompletion = nil
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
