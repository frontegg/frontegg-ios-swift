//
//  EmbeddedLoginPage.swift
//  
//
//  Created by David Frontegg on 13/09/2023.
//

import Foundation
import SwiftUI
import UIKit

public struct EmbeddedLoginPage: View {
    @EnvironmentObject var fronteggAuth: FronteggAuth
    
    public init() {}
    
    
    public var body: some View {
        ZStack {
            NavigationView{
                VStack(alignment: .center) {
                    ZStack{
                        FronteggWebView()
                        if fronteggAuth.webLoading {
                           DefaultLoader()
                       }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Back to login") {
                            fronteggAuth.pendingAppLink = nil
                            fronteggAuth.appLink = false
                            fronteggAuth.externalLink = false
                            fronteggAuth.login()
                        }
                    }
                }
                .navigationBarHidden(!fronteggAuth.externalLink)
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)

                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .center)
                .ignoresSafeArea(fronteggAuth.externalLink ? [] : [.all])

            }
            .navigationViewStyle(StackNavigationViewStyle())
            
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .center)
        .ignoresSafeArea()
        
    }
}

struct FronteggLoginPage_Previews: PreviewProvider {
    static var previews: some View {
        EmbeddedLoginPage()
    }
}
