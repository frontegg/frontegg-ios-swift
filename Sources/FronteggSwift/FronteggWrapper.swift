//
//  FronteggWrapper.swift
//  poc
//
//  Created by David Frontegg on 14/11/2022.
//

import SwiftUI


public struct FronteggWrapper<Content: View>: View {
    var content: () -> Content
    var loaderView: AnyView?
    @StateObject var fronteggAuth = try! FronteggAuth()
    
    
    public init(loaderView: AnyView, @ViewBuilder content: @escaping () -> Content) {
        self.content = content
        self.loaderView = loaderView
    }
    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
        self.loaderView = nil
    }
    public var body: some View {
        ZStack {
            if !fronteggAuth.initializing {
                if(fronteggAuth.pendingAppLink != nil){
                    FronteggLoginPage()
                } else {
                    Group(content: content)
                }
            }
            if fronteggAuth.showLoader {
                self.loaderView ?? AnyView {
                    Color(red: 0.95, green:  0.95, blue:  0.95).ignoresSafeArea(.all)
                    VStack {
                        ProgressView()
                    }
                    
                }
            }
        }
        .environmentObject(fronteggAuth)
        .onOpenURL { url in
            if(url.absoluteString.hasPrefix(fronteggAuth.baseUrl)){
                fronteggAuth.pendingAppLink = url
            }
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

