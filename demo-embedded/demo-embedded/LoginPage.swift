import SwiftUI
import FronteggSwift

struct LoginPage: View {
    @EnvironmentObject var fronteggAuth: FronteggAuth
    
    var body: some View {
        if fronteggAuth.isLoading {
            LoaderView()
        } else {
            
            ZStack() {
                Color.backgroundColor.ignoresSafeArea()
                
                ScrollView {
                    Spacer().frame(height: 150)
                    content
                    Spacer().frame(height: 200)
                }
                
            }
            .overlay(FronteggAppBar()
                .ignoresSafeArea(edges: .top),alignment: .top)
            .overlay(Footer()
                .ignoresSafeArea(edges: .bottom),alignment: .bottom)
        }
        
    }
    
    @ViewBuilder
    private var content: some View {
        if fronteggAuth.isLoading {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .primaryColor))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !fronteggAuth.isAuthenticated {
            LoginBody()
        } else {
            EmptyView()
        }
    }
}

struct LoginBody: View {
    @EnvironmentObject var fronteggAuth: FronteggAuth
    /// Refresh token from `POST /frontegg/identity/resources/users/v1/signUp` (response body `authResponse.refreshToken` or Set-Cookie). Used by Request Authorize.
    @State private var signUpRefreshToken: String = ""
    @State private var requestAuthorizeMessage: String?
    @State private var requestAuthorizeSuccess: Bool = false

    var body: some View {
        VStack {
            Spacer()
            CardView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("🤗")
                        .font(.system(size: 40))
                        .padding(.bottom, 16)

                    Text("Welcome!")
                        .font(.headlineMedium)
                        .foregroundColor(.textColor)
                    Text("This is Frontegg's sample app that will let you experiment with our authentication flows.")
                        .font(.bodyMedium)
                        .foregroundColor(.gray600)
                        .padding(.top, 8)
                        .padding(.bottom, 16)

                    VStack(spacing: 0) {
                        Button("Sign in") {
                            fronteggAuth.login()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        Button("Login with popup") {
                            fronteggAuth.directLoginAction(window: nil, type: "social-login", data: "apple", ephemeralSession: true)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        Button("Direct Apple login (provider)") {
                            fronteggAuth.directLoginAction(window: nil, type: "social-login", data: "apple")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        Button("Direct apple login") {
                            fronteggAuth.directLoginAction(
                                window: nil,
                                type: "direct",
                                data: "https://appleid.apple.com/auth/authorize?response_type=code&response_mode=form_post&redirect_uri=https%3A%2F%2Fauth.davidantoon.me%2Fidentity%2Fresources%2Fauth%2Fv2%2Fuser%2Fsso%2Fapple%2Fpostlogin&scope=openid+name+email&state=%7B%22oauthState%22%3A%22eyJGUk9OVEVHR19PQVVUSF9SRURJUkVDVF9BRlRFUl9MT0dJTiI6ImNvbS5mcm9udGVnZy5kZW1vOi8vYXV0aC5kYXZpZGFudG9vbi5tZS9pb3Mvb2F1dGgvY2FsbGJhY2siLCJGUk9OVEVHR19PQVVUSF9TVEFURV9BRlRFUl9MT0dJTiI6IjQ1MDVkMzljLTg0ZTctNDhiZi1hMzY3LTVmMjhmMmZlMWU1YiJ9%22%2C%22provider%22%3A%22apple%22%2C%22appId%22%3A%22%22%2C%22action%22%3A%22login%22%7D&client_id=com.frontegg.demo.client",
                                ephemeralSession: true
                            )
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        TextField("Refresh token (from signUp)", text: $signUpRefreshToken)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        Text("Use refresh token from POST /frontegg/identity/resources/users/v1/signUp (authResponse.refreshToken or Set-Cookie).")
                            .font(.caption)
                            .foregroundColor(.gray600)
                        Button("Request Authorize") {
                            requestAuthorizeWithSignUpToken()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(signUpRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if let msg = requestAuthorizeMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundColor(requestAuthorizeSuccess ? .green : .red)
                        }
                        Button("Login with Organization") {
                            FronteggApp.shared.loginOrganizationAlias = "test"
                            fronteggAuth.login()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("Login with Organization")
                        Button("Login with Passkeys") {
                            fronteggAuth.loginWithPasskeys()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding(24)

            }
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    /// Authorize using refresh token from `POST /frontegg/identity/resources/users/v1/signUp`.
    private func requestAuthorizeWithSignUpToken() {
        let token = signUpRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            requestAuthorizeMessage = "Enter a refresh token from signUp"
            requestAuthorizeSuccess = false
            return
        }
        requestAuthorizeMessage = nil
        Task {
            do {
                let user = try await fronteggAuth.requestAuthorizeAsync(refreshToken: token)
                requestAuthorizeMessage = "Logged in: \(user.email)"
                requestAuthorizeSuccess = true
            } catch {
                requestAuthorizeMessage = "Failed: \(error.localizedDescription)"
                requestAuthorizeSuccess = false
            }
        }
    }
}

// Обертка для карточки
struct CardView<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    var body: some View {
        content
            .cardStyle()
    }
}

#Preview {
    LoginPage()
}
