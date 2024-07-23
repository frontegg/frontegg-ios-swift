//
//  FronteggError.swift
//
//
//  Created by Nick Hagi on 17/07/2024.
//

import Foundation

public enum FronteggError: Error {
    case configError(Configuration)
    case authError(Authentication)
}
