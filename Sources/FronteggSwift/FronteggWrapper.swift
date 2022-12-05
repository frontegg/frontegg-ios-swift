//
//  FronteggWrapper.swift
//  poc
//
//  Created by David Frontegg on 14/11/2022.
//

import SwiftUI


public struct FronteggWrapper<Content: View>: View {
    var content: () -> Content
    @StateObject var fronteggAuth = try! FronteggAuth()
    
    
    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
    public var body: some View {
        ZStack {
            if fronteggAuth.showLoader {
                Color(red: 0.95, green:  0.95, blue:  0.95).ignoresSafeArea(.all)
                VStack {
                    ProgressView()
                }
            }
            if(fronteggAuth.pendingAppLink != nil){
                FronteggLoginPage()
            } else {
                Group(content: content)
            }
        }
        .environmentObject(fronteggAuth)
        .onOpenURL { url in
            if(url.absoluteString.hasPrefix(fronteggAuth.baseUrl)){
                print("App link: \(url)")
                fronteggAuth.loadAppLink(url)
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

