//
//  MyApp.swift
//  poc
//
//  Created by David Frontegg on 14/11/2022.
//

import SwiftUI
import FronteggSwift

struct MyApp: View {
    @EnvironmentObject var fronteggAuth: FronteggAuth

    
    var body: some View {
        ZStack{
            if !fronteggAuth.initializing {
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
                } else  {
                    FronteggLoginPage()
                }
            }
            if fronteggAuth.initializing || (!fronteggAuth.isAuthenticated && fronteggAuth.isLoading) {
                Color(red: 0.95, green:  0.95, blue:  0.95).ignoresSafeArea(.all)
                VStack {
                    Image("SplashIcon")
                        .resizable()
                        .frame(width: 100, height: 100)
                    ProgressView()
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
