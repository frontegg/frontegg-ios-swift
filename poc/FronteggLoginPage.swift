//
//  ContentView.swift
//  poc
//
//  Created by David Frontegg on 24/10/2022.
//

import SwiftUI


struct FronteggLoginPage: View {
    @EnvironmentObject var fronteggAuth: FronteggAuth
    
    var body: some View {
        VStack(alignment: .center) {
            SwiftUIWebView(fronteggAuth:fronteggAuth)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .center)
        .ignoresSafeArea()
            .background(Color.red)
            
            
    }
}

struct FronteggLoginPage_Previews: PreviewProvider {
    static var previews: some View {
        FronteggLoginPage()
    }
}
