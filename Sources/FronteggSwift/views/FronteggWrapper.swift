//
//  FronteggWrapper.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import SwiftUI



public struct FronteggWrapper<Content: View>: View {
    var content: () -> Content
    var loaderView: AnyView
    @StateObject var fronteggAuth = FronteggApp.shared.auth
    
    
    public init(loaderView: AnyView, @ViewBuilder content: @escaping () -> Content) {
        self.content = content
        self.loaderView = loaderView
    }
    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
        self.loaderView = AnyView(DefaultLoader())
    }
    public var body: some View {
        ZStack {
            if !fronteggAuth.initializing && fronteggAuth.pendingAppLink == nil {
                if(fronteggAuth.appLink != nil){
                    
                    

                } else {
                    Group(content: content)
                }
            }
            if fronteggAuth.showLoader || fronteggAuth.pendingAppLink != nil {
                self.loaderView
            }
        }
        .environmentObject(fronteggAuth)
        .onOpenURL { url in
            
            fronteggAuth.handleMagicLink(url)
//            if(url.absoluteString.hasPrefix(fronteggAuth.baseUrl)){
//                fronteggAuth.pendingAppLink = url
//            }
        }
    }
}

struct FronteggWrapper_Previews: PreviewProvider {
    static var previews: some View {
        FronteggWrapper {
            Text("asdasd")
        }
    }
}

