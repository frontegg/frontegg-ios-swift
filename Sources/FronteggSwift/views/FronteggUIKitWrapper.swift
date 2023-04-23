//
//  FronteggUIKitWrapper.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import SwiftUI

struct FronteggUIKitWrapper: View {
    var loaderView: AnyView
    var navigateToAuthenticated: () -> Void
    @StateObject var fronteggAuth = FronteggApp.shared.auth
    
    init(navigateToAuthenticated: @escaping () -> Void, loaderView: AnyView?) {
        self.navigateToAuthenticated = navigateToAuthenticated
        self.loaderView = loaderView ?? AnyView(DefaultLoader())
    }
    public var body: some View {
        ZStack {
            if !fronteggAuth.initializing && fronteggAuth.pendingAppLink == nil {
                if(fronteggAuth.appLink != nil){
                    FronteggLoginPage()
                } else {
                    if(fronteggAuth.isAuthenticated){
                        self.loaderView
                        .onAppear() {
                            self.navigateToAuthenticated()
                        }
                    }else {
                        FronteggLoginPage()
                    }
                }
            }
            if fronteggAuth.showLoader || fronteggAuth.pendingAppLink != nil {
                self.loaderView
            }
        }
        .environmentObject(fronteggAuth)
    }
}


