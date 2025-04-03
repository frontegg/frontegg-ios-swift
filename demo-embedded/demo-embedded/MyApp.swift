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
                VStack {
                    /// A button that logs in the user when pressed
                    Button {
                        fronteggAuth.login()
                    } label: {
                        Text("Login")
                    }.padding(.vertical, 30)

                    /// A button that logs in the user when pressed
                    Button {
                        fronteggAuth.directLoginAction(window: nil, type: "social-login", data: "apple", ephemeralSession: true)
                    } label: {
                        Text("Login with popup")
                    }.padding(.vertical, 30)

                    /// A button that direct apple logs in the user when pressed
                    Button {
                        fronteggAuth.directLoginAction(window: nil, type: "social-login", data: "apple")
                    } label: {
                        Text("Direct Apple login (provider)")
                    }.padding(.vertical, 30)

                    /// A button that direct apple logs in the user when pressed
                    Button {
                        fronteggAuth.directLoginAction(
                            window: nil,
                            type: "direct",
                            data: "https://appleid.apple.com/auth/authorize?response_type=code&response_mode=form_post&redirect_uri=https%3A%2F%2Fauth.davidantoon.me%2Fidentity%2Fresources%2Fauth%2Fv2%2Fuser%2Fsso%2Fapple%2Fpostlogin&scope=openid+name+email&state=%7B%22oauthState%22%3A%22eyJGUk9OVEVHR19PQVVUSF9SRURJUkVDVF9BRlRFUl9MT0dJTiI6ImNvbS5mcm9udGVnZy5kZW1vOi8vYXV0aC5kYXZpZGFudG9vbi5tZS9pb3Mvb2F1dGgvY2FsbGJhY2siLCJGUk9OVEVHR19PQVVUSF9TVEFURV9BRlRFUl9MT0dJTiI6IjQ1MDVkMzljLTg0ZTctNDhiZi1hMzY3LTVmMjhmMmZlMWU1YiJ9%22%2C%22provider%22%3A%22apple%22%2C%22appId%22%3A%22%22%2C%22action%22%3A%22login%22%7D&client_id=com.frontegg.demo.client",
                            ephemeralSession: true
                        )
                    } label: {
                        Text("Direct apple login")
                    }.padding(.vertical, 30)

                    /// A button that requests authorize with tokens logs in the user when pressed
                    Button {
                        Task {
                            do {
                                let user = try await fronteggAuth.requestAuthorizeAsync(refreshToken: "e3994bf8-e3f5-44d7-a3ba-d467d5b9a4f2")
                                print("Logged in user, \(user.email)")
                            } catch {
                                print("Failed to authenticate, \(error.localizedDescription)")
                            }
                        }
                    } label: {
                        Text("Request Authorize With Tokens")
                    }.padding(.vertical, 30)

                    /// A button that logs in with passkeys the user when pressed
                    Button {
                        fronteggAuth.loginWithPasskeys()
                    } label: {
                        Text("Login with Passkeys")
                    }.padding(.vertical, 30)
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
