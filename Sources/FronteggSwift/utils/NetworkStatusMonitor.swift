//
//  NetworkStatusMonitor.swift
//
//
//  Created by Nick Hagi on 18/09/2024.
//

import Foundation
import Network

struct NetworkStatusMonitor {

    private static let queue = DispatchQueue(label: "NetworkStatusMonitor")

    static var isActive: Bool {
        get async {
            let monitor = NWPathMonitor()
            let result = await withCheckedContinuation { continuation in

                monitor.pathUpdateHandler = { path in
                    switch path.status {
                    case .satisfied:
                        continuation.resume(returning: true)
                    default:
                        continuation.resume(returning: false)
                    }
                }

                monitor.start(queue: queue)
            }
            monitor.cancel()
            return result
        }
    }
}
