//
//  MyApp.swift
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
            if fronteggAuth.isAuthenticated {
                /// A tab view that displays the user's profile and tenants tabs
                TabView {
                    /// A tab that displays the user's profile information
                    ProfileTab()
                        .tabItem {
                            Image(systemName: "person.circle")
                            Text("Profile")
                        }
                    /// A tab that displays the user's tenants
                    TenantsTab()
                        .tabItem {
                            Image(systemName: "checklist")
                            Text("Tenants")
                        }
                }
            } else {
                /// A button that logs in the user when pressed
                Button {
                    fronteggAuth.login()
                } label: {
                    Text("Login Button")
                }
            }
        }
    }
}

struct MyApp_Previews: PreviewProvider {
    static var previews: some View {
        MyApp()
    }
}
