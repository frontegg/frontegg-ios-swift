//
//  MyApp.swift
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
                    TasksTab()
                        .tabItem {
                            Image(systemName: "checklist")
                            Text("Tasks")
                        }
                }
            }else{
                Button {
                    fronteggAuth.login { res in
                        switch res {
                        case .success(let user):
                            print("user: \(user)")
                        
                        case .failure(let error):
                            print("error: \(error)")
                        }
                        
                    }
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
