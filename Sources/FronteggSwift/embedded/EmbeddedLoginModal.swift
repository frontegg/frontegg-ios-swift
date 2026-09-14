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

                // Unanimated on purpose. This branch runs after authentication
                // succeeds, when the host app is already showing its own loader
                // underneath. An animated dismissal slides this loader — and the
                // spinner in it — down and off the screen over the host's
                // stationary spinner, which reads as the spinner jumping away and
                // back. Every other dismissal in the auth flow is already
                // unanimated for the same reason.
                DefaultLoader().onAppear() {
                    VCHolder.shared.vc?.presentedViewController?.dismiss(animated: false)
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
            guard !self.fronteggAuth.isAuthenticated else { return }
            guard let rootVC = VCHolder.shared.vc else { return }
            // Avoid canceling a newer embedded login if this onDisappear is delayed
            // after a replacement modal was already presented.
            if rootVC.presentedViewController is UIHostingController<EmbeddedLoginModal> {
                return
            }
            self.fronteggAuth.loginCompletion?(.failure(.authError(.operationCanceled)))
        }
        .environmentObject(fronteggAuth)
    }
}

struct EmbeddedLoginModal_Previews: PreviewProvider {
    static var previews: some View {
        EmbeddedLoginModal()
    }
}
