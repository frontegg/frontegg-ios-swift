//
//  ProfileTab.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import SwiftUI
import FronteggSwift

struct ProfileTab: View {
    
    @EnvironmentObject var fronteggAuth: FronteggAuth
    @State private var toastMessage: String? = nil
    
    var body: some View {
        NavigationView {
            VStack{
                ProfilePicture()
                    .padding(.top, 60)
                    .padding(.bottom, 40)
                
                ProfileInfo()
                
                Button("Register Passkeys") {
                    fronteggAuth.registerPasskeys()
                }
                Spacer()
                
                Button {
                    let maxAge = TimeInterval(60)
                    let isSteppedUp = fronteggAuth.isSteppedUp(maxAge: maxAge)
                    if isSteppedUp {
                        showToast(message: "No need step up right now!")
                        return
                    }
                    
                    Task {
                        await fronteggAuth.stepUp(maxAge: maxAge) { result in
                            switch result {
                            case .success(let user):
                                showToast(message: "Finished \(user)")
                            case .failure(let error):
                                showToast(message: "ERROR: \(error.localizedDescription)")
                            }
                        }
                    }
                } label: {
                    Text("Step Up")
                }
                Button("Logout") {
                    fronteggAuth.logout()
                }
                .foregroundColor(.red)
                .font(.title2)
                .padding(.bottom, 40)
            }
            
            .navigationTitle("Profile")
        }
        if let message = toastMessage {
            VStack {
                Spacer()
                ToastView(message: message)
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                toastMessage = nil
                            }
                        }
                    }
            }
            .animation(.easeInOut, value: toastMessage)
        }
    }
    
    // Show toast using SwiftUI approach
    private func showToast(message: String) {
        withAnimation {
            toastMessage = message
        }
    }
}

// Reusable ToastView Component
struct ToastView: View {
    let message: String
    
    var body: some View {
        Text(message)
            .padding()
            .background(Color.black.opacity(0.7))
            .foregroundColor(.white)
            .cornerRadius(10)
            .padding(.bottom, 50)
    }
}

struct ProfileTab_Previews: PreviewProvider {
    static var previews: some View {
        ProfileTab()
    }
}
