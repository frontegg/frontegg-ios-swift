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
                /// A view that allows the user to select their region
                SelectRegionView()
            } else if fronteggAuth.isAuthenticated {
                /// A tab view that displays the user's profile and tenants tabs
                TabView {
                    /// A view that displays the user's profile information
                    ProfileTab()
                        .tabItem {
                            Image(systemName: "person.circle")
                            Text("Profile")
                        }
                    /// A view that displays the user's tenants
                    TenantsTab()
                        .tabItem {
                            Image(systemName: "checklist")
                            Text("Tenants")
                        }
                }
            } else {
                if (fronteggAuth.lateInit) {
                    /// A view that allows the user to select their region
                    VStack{
                        /// A button that allows the user to select EU region
                        Button("EU") {
                            FronteggApp.shared.manualInit(baseUrl: "https://autheu.davidantoon.me", cliendId: "b6adfe4c-d695-4c04-b95f-3ec9fd0c6cca")
                        }.padding(.bottom, 40)
                        /// A button that allows the user to select US region
                        Button("US") {
                            FronteggApp.shared.manualInit(baseUrl: "https://authus.davidantoon.me", cliendId: "d7d07347-2c57-4450-8418-0ec7ee6e096b")
                        }
                    }
                }else {
                    /// A view that displays the user's profile and tenants tabs
                    DefaultLoader().onAppear(){
                        /// Auto logs in
                        if(!fronteggAuth.isAuthenticated && !fronteggAuth.initializing){
                            fronteggAuth.login()
                        }
                    }
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
