//
//  FronteggWrapper.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import SwiftUI



public struct FronteggWrapper<Content: View>: View {
    var content: () -> Content
    @StateObject var fronteggAuth = FronteggApp.shared.auth
    
    
    public init(loaderView: AnyView, @ViewBuilder content: @escaping () -> Content) {
        self.content = content
        DefaultLoader.customLoaderView = loaderView
    }
    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
    public var body: some View {
        ZStack {
            if fronteggAuth.initializing
                || fronteggAuth.showLoader
                || fronteggAuth.appLink {
                DefaultLoader()
                    .accessibilityIdentifier("DefaultLoaderRoot")
                    .accessibilityValue(loaderDebugValue)
            } else {
                Group(content: content)
            }
        }
        .environmentObject(fronteggAuth)
        .onOpenURL { url in
            if(fronteggAuth.handleOpenUrl(url)){
                return
            }
        }
    }

    private var loaderDebugValue: String {
        "initializing=\(fronteggAuth.initializing)," +
        "showLoader=\(fronteggAuth.showLoader)," +
        "appLink=\(fronteggAuth.appLink)," +
        "isLoading=\(fronteggAuth.isLoading)," +
        "isAuthenticated=\(fronteggAuth.isAuthenticated)," +
        "isOfflineMode=\(fronteggAuth.isOfflineMode)"
    }
}

struct FronteggWrapper_Previews: PreviewProvider {
    static var previews: some View {
        FronteggWrapper {
            Text("asdasd")
        }
    }
}
