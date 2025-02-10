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
                        }.padding(.vertical, 30)
                        
                        Button {
                            fronteggAuth.socialLogin(window: nil, provider: .google)
                        } label: {
                            Text("Login with google")
                        }.padding(.vertical, 30)
                        
                        
                        Button {
                            fronteggAuth.socialLogin(window: nil, provider: .apple, ephemeralSession: true)
                        } label: {
                            Text("Login with popup")
                        }.padding(.vertical, 30)
                        
                        
                        Button {
                            fronteggAuth.socialLogin(window: nil, provider: .apple)
                        } label: {
                            Text("Direct Apple login (provider)")
                        }.padding(.vertical, 30)
                        
                        Button {
                            fronteggAuth.directLogin(window: nil, url: "https://appleid.apple.com/auth/authorize?response_type=code&response_mode=form_post&redirect_uri=https%3A%2F%2Fauth.davidantoon.me%2Fidentity%2Fresources%2Fauth%2Fv2%2Fuser%2Fsso%2Fapple%2Fpostlogin&scope=openid+name+email&state=%7B%22oauthState%22%3A%22eyJGUk9OVEVHR19PQVVUSF9SRURJUkVDVF9BRlRFUl9MT0dJTiI6ImNvbS5mcm9udGVnZy5kZW1vOi8vYXV0aC5kYXZpZGFudG9vbi5tZS9pb3Mvb2F1dGgvY2FsbGJhY2siLCJGUk9OVEVHR19PQVVUSF9TVEFURV9BRlRFUl9MT0dJTiI6IjQ1MDVkMzljLTg0ZTctNDhiZi1hMzY3LTVmMjhmMmZlMWU1YiJ9%22%2C%22provider%22%3A%22apple%22%2C%22appId%22%3A%22%22%2C%22action%22%3A%22login%22%7D&client_id=com.frontegg.demo.client", ephemeralSession: true)
                        } label: {
                            Text("Direct apple login")
                        }.padding(.vertical, 30)
                        
                        
                        Button {
                            
                            Task {
                                do {
                                    let user = try await fronteggAuth.requestAuthorizeAsync(refreshToken: "e3994bf8-e3f5-44d7-a3ba-d467d5b9a4f2")
                                    print("Logged in user, \(user.email)")
                                }catch {
                                    print("failed to authenticate, \(error.localizedDescription)")
                                }
                                
                            }
//                            fronteggAuth.requestAuthorize(refreshToken: "f3291a85-7cfd-4319-9e24-fab68d3eba1f", deviceTokenCookie: nil) { result in
//                                switch (result){
//                                case .success(let user):
//                                    print("Logged in user, \(user.email)")
//                                    
//                                case .failure(let error):
//                                    print("failed to authenticate, \(error.localizedDescription)")
//                                }
//                            }
                        } label: {
                            Text("Request Authroize With tokens")
                        }.padding(.vertical, 30)
                        
                        
                        
                        
                        Button {
                            fronteggAuth.loginWithPasskeys()
                            
                            
                        }  label: {
                            Text("Login with passkeys")
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
