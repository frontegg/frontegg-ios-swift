//
//  demo_embeddedApp.swift
//  demo-embedded
//
//  Created by David Frontegg on 13/09/2023.
//

import SwiftUI
import FronteggSwift

@main
struct demo_embeddedApp: App {
    var body: some Scene {
        WindowGroup {
            FronteggWrapper() {
                MyApp()
            }
        }
    }
}
