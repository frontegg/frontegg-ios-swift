//
//  demo_embeddedApp.swift
//  demo-embedded
//
//  Created by David Frontegg on 13/09/2023.
//

import SwiftUI
import FronteggSwift

/// The main entry point for the demo application.
@main
struct demo_embeddedApp: App {
    @StateObject private var bootstrapper = DemoEmbeddedBootstrapper()

    var body: some Scene {
        WindowGroup {
            Group {
                if bootstrapper.isReady {
                    FronteggWrapper() {
                        MyApp()
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
