//
//  FronteggAppBar.swift
//  demo-embedded
//
//  Created by Oleksii Minaiev on 29.05.2025.
//

import SwiftUI
import FronteggSwift

struct FronteggAppBar: View {
    @EnvironmentObject var fronteggAuth: FronteggAuth
    
    var body: some View {
        HStack {
            HStack{
                HStack(spacing: 16) {
                    Image("frontegg-logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 24)
                    
                    Image("swift-icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                }
                .padding(.leading, 24)
                .frame(width: 200)
                
                Spacer()
                
                // Actions section
                if fronteggAuth.isAuthenticated {
                    Button(action: {
                        fronteggAuth.logout()
                    }) {
                        Text("Logout")
                            .foregroundColor(.textColor)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 2)
                            .frame(minWidth: 40, maxWidth: 120, minHeight: 32, maxHeight: 32)
                            .background(Color.backgroundColor)
                    }
                    .padding(.trailing, 24)
                }
            }.padding(.top, 60)
           
            
        }
        .frame(height: 132)
        .background(Color.white)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 0)
        
    }
}

// MARK: - Preview
#Preview {
   FronteggAppBar()
}
