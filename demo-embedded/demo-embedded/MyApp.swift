//
//  MyApp.swift
//  demo-embedded
//
//  Created by David Frontegg on 14/11/2022.
//

import SwiftUI
import FronteggSwift

struct MyApp: View {
    @EnvironmentObject var fronteggAuth: FronteggAuth
    
    var body: some View {
        ZStack {
            if fronteggAuth.isAuthenticated {
                TabView {
                    ProfileTab()
                        .tabItem {
                            Image(systemName: "person.circle")
                            Text("Profile")
                        }
                    TenantsTab()
                        .tabItem {
                            Image(systemName: "checklist")
                            Text("Tenants")
                        }
                }
            } else {
                
                if(!fronteggAuth.isAuthenticated){
                    VStack {
                        Button {
                            fronteggAuth.login()
                        } label: {
                            Text("Login")
                        }.padding(.vertical, 20)
                        
                        Button {
                            fronteggAuth.directLoginAction(window: nil, type: "social-login", data: "google")
                        } label: {
                            Text("Login with popup")
                        }
                    }
                    
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
