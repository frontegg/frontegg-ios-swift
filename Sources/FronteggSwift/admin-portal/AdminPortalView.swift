//
//  AdminPortalView.swift
//  FronteggSwift
//
//  POC: SwiftUI entry point for the embedded admin portal.
//
//  Presents the hosted admin portal (`${baseUrl}/oauth/portal`) inside an
//  in-app WKWebView with native iOS chrome (top bar + Done button) so the
//  end user never leaves the app and never has to re-authenticate.
//

import SwiftUI
import WebKit

@available(iOS 14.0, *)
public struct AdminPortalView: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var loginRedirectDetected: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            content
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
    }

    private var topBar: some View {
        HStack {
            Button(action: dismiss) {
                Text("Done")
                    .font(.body)
                    .fontWeight(.semibold)
            }
            Spacer()
            Text("Admin Portal")
                .font(.headline)
            Spacer()
            // Symmetry filler so the title stays centered.
            Text("Done")
                .font(.body)
                .fontWeight(.semibold)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(UIColor.systemBackground))
    }

    @ViewBuilder
    private var content: some View {
        if loginRedirectDetected {
            authBridgingFailedState
        } else {
            AdminPortalWebView(onNavigationFailure: { _ in
                DispatchQueue.main.async {
                    loginRedirectDetected = true
                }
            })
        }
    }

    private var authBridgingFailedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundColor(.orange)
            Text("Couldn't open the admin portal")
                .font(.headline)
            Text("The portal asked us to log in again. The session may have expired.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Close", action: dismiss)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dismiss() {
        presentationMode.wrappedValue.dismiss()
    }
}
