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
            
            if fronteggAuth.isRegional && fronteggAuth.selectedRegion == nil {
                SelectRegionView()
            } else if fronteggAuth.isAuthenticated {
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
                
                if(fronteggAuth.lateInit) {
                    
                    VStack{
                        Button("EU") {
                            FronteggApp.shared.manualInit(baseUrl: "https://autheu.davidantoon.me", cliendId: "b6adfe4c-d695-4c04-b95f-3ec9fd0c6cca")
                        }.padding(.bottom, 40)
                        
                        Button("US") {
                            FronteggApp.shared.manualInit(baseUrl: "https://authus.davidantoon.me", cliendId: "d7d07347-2c57-4450-8418-0ec7ee6e096b")
                        }
                    }
                }else {
                    DefaultLoader().onAppear(){
                        if(!fronteggAuth.isAuthenticated && !fronteggAuth.initializing){
                            fronteggAuth.login()
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
