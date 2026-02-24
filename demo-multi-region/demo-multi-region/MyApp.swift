//
//  MyApp.swift
//  demo-embedded
//
//  Created by David Frontegg on 14/11/2022.
//

import SwiftUI
import FronteggSwift

/// The main view of the demo application.
/// This component displays the user's profile and tenants tabs.
struct MyApp: View {
    /// The Frontegg authentication state object
    @EnvironmentObject var fronteggAuth: FronteggAuth
    
    var body: some View {
        ZStack {
            /// A view that displays the user's profile and tenants tabs
            if fronteggAuth.isRegional && fronteggAuth.selectedRegion == nil {
                SelectRegionView()
            } else if fronteggAuth.isAuthenticated {
                UserPage()
            } else {
                if (fronteggAuth.lateInit) {
                    /// A view that allows the user to select their region
                    VStack{
                        /// A button that allows the user to select EU region
                        Button("EU") {
                            FronteggApp.shared.manualInit(baseUrl: "https://app-x4gr8g28fxr5.frontegg.com", cliendId: "5f493de4-01c5-4a61-8642-fca650a6a9dc")
                        }.padding(.bottom, 40)
                        /// A button that allows the user to select US region
                        Button("US") {
                            FronteggApp.shared.manualInit(baseUrl: "https://authus.davidantoon.me", cliendId: "d7d07347-2c57-4450-8418-0ec7ee6e096b")
                        }
                    }
                } else {
                    LoginPage()
                }
                
            }
        }
    }
}

// Preview provider for SwiftUI previews
struct MyApp_Previews: PreviewProvider {
    static var previews: some View {
        MyApp()
    }
}
