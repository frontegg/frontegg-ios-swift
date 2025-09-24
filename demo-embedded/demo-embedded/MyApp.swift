//
//  MyApp.swift
//  demo-embedded
//
//  Created by David Frontegg on 14/11/2022.
//

import SwiftUI
import FronteggSwift
import Combine

/// The main view of the demo application.
/// This component displays the user's profile and tenants tabs.
struct MyApp: View {
    /// The Frontegg authentication state object
    @EnvironmentObject var fronteggAuth: FronteggAuth
    
    @State private var subscribers = Set<AnyCancellable>()
    
    var body: some View {
        ZStack {
            if fronteggAuth.isAuthenticated {
                UserPage()
            } else {
                LoginPage()
            }
        }.onAppear() {
            fronteggAuth.$accessToken.sink { accessToken in
                print("AccessToken: \(accessToken ?? "none")")
            }.store(in: &self.subscribers)
        }.onDisappear() {
            self.subscribers.forEach { c in
                c.cancel()
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
