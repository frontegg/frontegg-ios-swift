//
//  AdminPortalView.swift
//  FronteggSwift
//
//  POC: SwiftUI entry point for the embedded admin portal.
//
//  Native iOS chrome (top bar + Done button) wrapping a WKWebView that loads
//  `${baseUrl}/oauth/portal`. Reuses any web-side cookies already present
//  in the shared cookie store; otherwise the portal renders its own login.
//

import SwiftUI
import WebKit

@available(iOS 14.0, *)
public struct AdminPortalView: View {
    @Environment(\.presentationMode) private var presentationMode

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            AdminPortalWebView()
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

    private func dismiss() {
        presentationMode.wrappedValue.dismiss()
    }
}
