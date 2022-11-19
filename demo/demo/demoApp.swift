//
//  demoApp.swift
//  demo
//
//  Created by David Frontegg on 19/11/2022.
//

import SwiftUI
import FronteggSwift

@main
struct demoApp: App {
    var body: some Scene {
        WindowGroup {
            FronteggWrapper {
                MyApp()
            }
        }
    }
}
