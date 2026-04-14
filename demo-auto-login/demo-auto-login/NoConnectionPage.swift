//
//  NoConnectionPage.swift
//  demo-auto-login
//

import SwiftUI
import FronteggSwift

struct NoConnectionPage: View {
    @EnvironmentObject private var fronteggAuth: FronteggAuth

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.slash")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundColor(.red)

            Text("No Connection")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            Text("It looks like you're offline.\nPlease check your internet connection and try again.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Button {
                fronteggAuth.recheckConnection()
            } label: {
                Text("Retry")
                    .fontWeight(.semibold)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
            .accessibilityIdentifier("RetryConnectionButton")
        }
        .padding()
        .accessibilityIdentifier("NoConnectionPageRoot")
        .onAppear {
            if AutoLoginTestMode.isEnabled {
                AutoLoginUITestDiagnostics.shared.markNoConnectionPageSeen()
            }
        }
    }
}
