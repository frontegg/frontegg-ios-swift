//
//  FronteggWrapper.swift
//  poc
//
//  Created by David Frontegg on 14/11/2022.
//

import SwiftUI


struct FronteggWrapper<Content: View>: View {
    var content: () -> Content
    @StateObject var fronteggAuth = FronteggAuth()
    
    
    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
    var body: some View {
        Group(content: content)
            .environmentObject(fronteggAuth)
            
    }
}

struct FronteggWrapper_Previews: PreviewProvider {
    static var previews: some View {
        FronteggWrapper {
            Text("asdasd")
        }
    }
}

