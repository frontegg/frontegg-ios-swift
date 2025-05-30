//
//  Footer.swift
//  demo-embedded
//
//  Created by Oleksii Minaiev on 29.05.2025.
//

import SwiftUI

struct Footer: View {
    let showSignUpBanner: Bool
    
    init(showSignUpBanner: Bool = true) {
        self.showSignUpBanner = showSignUpBanner
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if showSignUpBanner {
                signUpBanner
                Spacer().frame(height: 16)
            }
            
            HStack {
                docsButton
                Spacer()
                socialButtons
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)

        .background(Color.white)
        .shadow(color: Color.black.opacity(0.12), radius: 1, x: 0, y: 0)
    }
    
    private var signUpBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This sample uses Frontegg's default credentials.\nSign up to use your own configurations")
                .font(.bodySmall)
            
            Button(action: {
                if let url = URL(string: "https://frontegg-prod.frontegg.com/oauth/account/sign-up") {
                    UIApplication.shared.open(url)
                }
            }) {
                Text("Sign-up")
                    .foregroundColor(Color(hex: "4461F2"))
                    .font(.bodySmall.weight(.medium))
                Spacer().frame(width: .infinity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(hex: "F5F8FF"))
        .cornerRadius(8)
    }
    
    private var docsButton: some View {
        Button(action: {
            if let url = URL(string: "https://ios-swift-guide.frontegg.com/#/") {
                UIApplication.shared.open(url)
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 16))
                Text("Visit Docs")
                    .font(.bodySmall)
                    .fontSize(16)
                Spacer().frame(width: 20)
            }
            
        }
        .foregroundColor(.black)
        .frame(minWidth: 24, maxWidth: 120, minHeight: 32, maxHeight: 32)
    }
    
    private var socialButtons: some View {
        HStack(spacing: 8) {
            Button(action: {
                if let url = URL(string: "https://github.com/frontegg/frontegg-ios-swift") {
                    UIApplication.shared.open(url)
                }
            }) {
                Image("github-icon")
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            .frame(width: 24, height: 24)
            
            Button(action: {
                if let url = URL(string: "https://slack.com/oauth/authorize?client_id=1234567890.1234567890&scope=identity.basic,identity.email,identity.team,identity.avatar") {
                    UIApplication.shared.open(url)
                }
            }) {
                Image("slack-icon")
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            .frame(width: 24, height: 24)
        }
    }
}

// MARK: - Font Size Extension
extension View {
    func fontSize(_ size: CGFloat) -> some View {
        self.font(.system(size: size))
    }
}

#Preview {
    Footer()
}
