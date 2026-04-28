//
//  AdminPortalView.swift
//  FronteggSwift
//
//  POC: SwiftUI entry point for the embedded admin portal.
//
//  Renders the WKWebView edge-to-edge — no native chrome. Dismissal is
//  via the host presentation's swipe-down gesture (use `.sheet` to
//  present) or via the portal's own X button, which calls window.close()
//  and is bridged through to SwiftUI's dismiss.
//

import SwiftUI
import WebKit

@available(iOS 14.0, *)
public struct AdminPortalView: View {
    @Environment(\.presentationMode) private var presentationMode

    public init() {}

    public var body: some View {
        AdminPortalWebView(onClose: dismiss)
            .ignoresSafeArea(edges: .bottom)
    }

    private func dismiss() {
        presentationMode.wrappedValue.dismiss()
    }
}
