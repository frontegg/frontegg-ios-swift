//
//  ProfileTab.swift
//
//  Created by David Frontegg on 14/11/2022.
//

import SwiftUI
import FronteggSwift

/// A view that displays the user's profile information and picture.
/// This component shows the user's profile picture and information in a vertical stack.
struct ProfileTab: View {
    /// The Frontegg authentication state object
    @EnvironmentObject var fronteggAuth: FronteggAuth
    @State private var toastMessage: String? = nil
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack {
                    /// A component that displays the user's profile picture
                    ProfilePicture()
                        .padding(.top, 60)
                        .padding(.bottom, 40)
                    
                    /// A component that displays the user's profile information
                    ProfileInfo()
                    
                    /// A button that registers passkeys when pressed
                    Button("Register Passkeys") {
                        fronteggAuth.registerPasskeys()
                    }
                    Spacer()

                    /// A button that steps up the user when pressed
                    Button {
                        let maxAge = TimeInterval(60)
                        let isSteppedUp = fronteggAuth.isSteppedUp(maxAge: maxAge)
                        if isSteppedUp {
                            showToast(message: "No need to step up right now!")
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
                    /// A button that logs out the user when pressed
                    Button("Logout") {
                        fronteggAuth.logout()
                    }
                    .foregroundColor(.red)
                    .font(.title2)
                    .padding(.bottom, 40)
                }
                .navigationTitle("Profile")
                
                // ToastView Layered Above Content
                if let message = toastMessage {
                    ToastView(message: message)
                        .transition(.opacity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation {
                                    toastMessage = nil
                                }
                            }
                        }
                        .padding(.bottom, 50)
                }
            }
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
            .background(Color.black.opacity(0.8))
            .foregroundColor(.white)
            .cornerRadius(10)
            .padding()
            .transition(.opacity)
    }
}

// Preview provider for SwiftUI previews
struct ProfileTab_Previews: PreviewProvider {
    static var previews: some View {
        ProfileTab()
    }
}

