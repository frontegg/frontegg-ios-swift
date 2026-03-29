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
    @ObservedObject private var diagnostics = DemoEmbeddedUITestDiagnostics.shared
    
    var body: some View {
        ZStack {
            if fronteggAuth.isLoading {
                // Loading
                LoaderView()
                    .overlay(alignment: .topLeading) {
                        ScreenMarker(identifier: "LoaderView")
                    }
            } else if fronteggAuth.isAuthenticated {
                if fronteggAuth.user != nil {
                    // User is logged in with full user data
                    UserPage()
                        .overlay(alignment: .topLeading) {
                            ScreenMarker(identifier: "UserPageRoot")
                        }
                } else {
                    // Authenticated but user data unavailable (offline with cached token, no offlineUser)
                    VStack {
                        Text("Authenticated (offline)")
                            .font(.headline)
                        Text("User details will load when connectivity is restored.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .overlay(alignment: .topLeading) {
                        ScreenMarker(identifier: "AuthenticatedOfflineRoot")
                    }
                }
            } else {
                // User is NOT logged in
                if fronteggAuth.isOfflineMode {
                    // disable authentication process if no internet
                    NoConnectionPage()
                        .overlay(alignment: .topLeading) {
                            ScreenMarker(identifier: "NoConnectionPageRoot")
                        }
                } else {
                    // display login page if NOT logged in and connected to internet
                    LoginPage()
                        .overlay(alignment: .topLeading) {
                            ScreenMarker(identifier: "LoginPageRoot")
                        }
                }
            }
            if DemoEmbeddedTestMode.isEnabled {
                if diagnostics.noConnectionPageSeenEver {
                    ScreenMarker(identifier: "NoConnectionPageSeenEver")
                }
                if fronteggAuth.isOfflineMode {
                    ScreenMarker(
                        identifier: fronteggAuth.isAuthenticated
                            ? "AuthenticatedOfflineModeEnabled"
                            : "UnauthenticatedOfflineModeEnabled"
                    )
                }
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

private struct ScreenMarker: View {
    let identifier: String

    var body: some View {
        Text(identifier)
            .font(.system(size: 1))
            .foregroundColor(.clear)
            .accessibilityIdentifier(identifier)
    }
}
