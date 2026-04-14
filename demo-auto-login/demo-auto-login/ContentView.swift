//
//  ContentView.swift
//  demo-auto-login
//
//  Auto-login pattern: when unauthenticated, directly show the Frontegg
//  embedded login WebView instead of an intermediate landing page.
//

import SwiftUI
import FronteggSwift
import Combine

struct ContentView: View {
    @EnvironmentObject var fronteggAuth: FronteggAuth

    @State private var subscribers = Set<AnyCancellable>()
    @ObservedObject private var diagnostics = AutoLoginUITestDiagnostics.shared

    var body: some View {
        ZStack {
            if fronteggAuth.isLoading || fronteggAuth.initializing || fronteggAuth.showLoader {
                LoaderView()
                    .overlay(alignment: .topLeading) {
                        ScreenMarker(identifier: "LoaderView")
                    }
            } else if fronteggAuth.isAuthenticated {
                if fronteggAuth.user != nil {
                    ProfileView()
                        .overlay(alignment: .topLeading) {
                            ScreenMarker(identifier: "ProfileViewRoot")
                        }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Authenticated (offline)")
                            .font(.headline)
                        Text("User details will load when connectivity is restored.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .overlay(alignment: .topLeading) {
                        ScreenMarker(identifier: "AuthenticatedOfflineRoot")
                    }
                }
            } else if fronteggAuth.isOfflineMode {
                NoConnectionPage()
                    .overlay(alignment: .topLeading) {
                        ScreenMarker(identifier: "NoConnectionPageRoot")
                    }
            } else {
                // AUTO-LOGIN: directly show embedded login WebView
                FronteggWebView()
                    .overlay(alignment: .topLeading) {
                        ScreenMarker(identifier: "AutoLoginWebViewRoot")
                    }
            }

            // E2E diagnostic markers
            if AutoLoginTestMode.isEnabled {
                e2eDiagnosticMarkers
            }
        }
        .onAppear {
            fronteggAuth.$accessToken.sink { accessToken in
                print("AccessToken: \(accessToken ?? "none")")
            }.store(in: &self.subscribers)
        }
        .onDisappear {
            self.subscribers.forEach { $0.cancel() }
        }
    }

    @ViewBuilder
    private var e2eDiagnosticMarkers: some View {
        if diagnostics.noConnectionPageSeenEver {
            ScreenMarker(identifier: "NoConnectionPageSeenEver")
        }
        if fronteggAuth.isOfflineMode {
            ScreenMarker(
                identifier: fronteggAuth.isAuthenticated
                    ? "AuthenticatedOfflineModeEnabled"
                    : "UnauthenticatedOfflineModeEnabled"
            )
        }
        ScreenValueMarker(identifier: "RootIsAuthenticatedValue",
                          value: fronteggAuth.isAuthenticated ? "1" : "0")
        ScreenValueMarker(identifier: "RootIsOfflineModeValue",
                          value: fronteggAuth.isOfflineMode ? "1" : "0")
        ScreenValueMarker(identifier: "RootIsLoadingValue",
                          value: fronteggAuth.isLoading ? "1" : "0")
        ScreenValueMarker(identifier: "RootInitializingValue",
                          value: fronteggAuth.initializing ? "1" : "0")
        ScreenValueMarker(identifier: "RootShowLoaderValue",
                          value: fronteggAuth.showLoader ? "1" : "0")
        ScreenValueMarker(identifier: "RootHasUserValue",
                          value: fronteggAuth.user != nil ? "1" : "0")
    }
}

// MARK: - E2E Accessibility Markers

private struct ScreenMarker: View {
    let identifier: String

    var body: some View {
        Text(identifier)
            .font(.system(size: 1))
            .foregroundColor(.clear)
            .accessibilityIdentifier(identifier)
    }
}

private struct ScreenValueMarker: View {
    let identifier: String
    let value: String

    var body: some View {
        Text(value)
            .font(.system(size: 1))
            .foregroundColor(.clear)
            .accessibilityIdentifier(identifier)
    }
}
