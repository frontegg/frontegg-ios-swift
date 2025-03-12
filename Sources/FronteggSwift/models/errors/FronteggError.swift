//
//  FronteggError.swift
//
//
//  Created by Nick Hagi on 17/07/2024.
//

import Foundation

public enum FronteggError: LocalizedError {
    case configError(Configuration)
    case authError(Authentication)
    case networkError(Authentication)

    public var errorDescription: String? {
        switch self {
            case .configError(let error): error.errorDescription
            case .authError(let error): error.errorDescription
            case .networkError(let error): error.errorDescription
        }
    }
}
