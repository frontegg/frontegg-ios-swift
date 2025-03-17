//
//  Storage.swift
//  FronteggSwift
//
//  Created by Oleksii Minaiev on 05.02.2025.
//

import Foundation

class FronteggInnerStorage {
    static let shared = FronteggInnerStorage()
    public var bundleIdentifier: String
    
    init() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            fatalError(FronteggError.configError(.couldNotGetBundleID(Bundle.main.bundlePath)).localizedDescription)
        }
        self.bundleIdentifier = bundleIdentifier
    }
}
