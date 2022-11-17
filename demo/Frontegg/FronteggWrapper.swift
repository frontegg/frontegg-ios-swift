//
//  FronteggWrapper.swift
//  poc
//
//  Created by David Frontegg on 14/11/2022.
//

import SwiftUI


struct FronteggWrapper<Content: View>: View {
    var content: () -> Content
    @StateObject var fronteggAuth = try! FronteggAuth()
    
    
    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
    var body: some View {
        ZStack {
            Group(content: content)
        }
        .environmentObject(fronteggAuth)
        .onOpenURL { url in
            
            print("Testing Url \(url)")
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

