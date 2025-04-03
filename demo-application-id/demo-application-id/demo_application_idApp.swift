import SwiftUI
import FronteggSwift

/// The main entry point for the demo application.
@main
struct demoApplicationIdApp: App {
    var body: some Scene {
        WindowGroup {
            FronteggWrapper() {
                MyApp()
            }
        }
    }
}
