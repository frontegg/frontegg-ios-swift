//
//  pocApp.swift
//  poc
//
//  Created by David Frontegg on 24/10/2022.
//

import SwiftUI

@main
struct AcmeApp: App {
    var body: some Scene {
        WindowGroup {
            FronteggWrapper{
                MyApp()
            }
        }
    }
    
}
