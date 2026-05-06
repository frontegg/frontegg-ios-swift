//
//  AdminPortalView.swift
//  FronteggSwift
//
//  POC: SwiftUI entry point for the embedded admin portal.
//
//  Renders the WKWebView edge-to-edge over a solid background so the
//  host app's content can't bleed through any seams. Dismissal is via
//  the sheet's swipe-down gesture or the portal's own X button (bridged
//  through window.close()).
//

import SwiftUI
import WebKit

@available(iOS 14.0, *)
public struct AdminPortalView: View {
    @Environment(\.presentationMode) private var presentationMode

    public init() {}

    public var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
            AdminPortalWebView(onClose: dismiss)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func dismiss() {
        presentationMode.wrappedValue.dismiss()
    }
}
