//
//  ContentView.swift
//
//  Created by David Frontegg on 24/10/2022.
//

import SwiftUI

public struct FronteggLoginPage: View {
    @EnvironmentObject var fronteggAuth: FronteggAuth
    
    public init(){}
    public var body: some View {
        let webView = FronteggWebView(fronteggAuth)
        ZStack {
            NavigationView{
                VStack(alignment: .center) {
                    webView
                }
                
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Back to login") {
                            fronteggAuth.accessToken = nil
                            fronteggAuth.refreshToken = nil
                            fronteggAuth.user = nil
                            fronteggAuth.isAuthenticated = false
                            fronteggAuth.isLoading = true
                            fronteggAuth.initializing = true
                            fronteggAuth.pendingAppLink = nil
                            fronteggAuth.externalLink = false
                            fronteggAuth.logout()
                        }
                    }
                }
                .navigationBarHidden(!fronteggAuth.externalLink)
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .center)
                
                .ignoresSafeArea(fronteggAuth.externalLink ? [] : [.all])
                
            }
            
            if fronteggAuth.showLoader {
                Color(red: 0.95, green:  0.95, blue:  0.95).ignoresSafeArea(.all)
                VStack {
                    ProgressView()
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .center)
        .ignoresSafeArea()
        
    }
}

struct FronteggLoginPage_Previews: PreviewProvider {
    static var previews: some View {
        FronteggLoginPage()
    }
}
