//
//  ContentView.swift
//  poc
//
//  Created by David Frontegg on 24/10/2022.
//

import SwiftUI


public struct FronteggLoginPage: View {
    @EnvironmentObject var fronteggAuth: FronteggAuth
    
    public init(){}
    public var body: some View {
        VStack(alignment: .center) {
            FronteggWebView(fronteggAuth:fronteggAuth)
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
