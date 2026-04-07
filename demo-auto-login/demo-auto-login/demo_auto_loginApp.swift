//
//  demo_auto_loginApp.swift
//  demo-auto-login
//

import SwiftUI
import FronteggSwift

@main
struct demo_auto_loginApp: App {
    @StateObject private var bootstrapper = AutoLoginBootstrapper()

    var body: some Scene {
        WindowGroup {
            Group {
                if bootstrapper.isReady {
                    FronteggWrapper {
                        ContentView()
                    }
                } else {
                    LoaderView()
                        .overlay(alignment: .topLeading) {
                            Text("BootstrapLoaderView")
                                .font(.system(size: 1))
                                .foregroundColor(.clear)
                                .accessibilityIdentifier("BootstrapLoaderView")
                        }
                }
            }
        }
    }
}
