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
                    }
                }
                .padding(24)
            }
            .padding(.horizontal, 24)
            Spacer()
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
