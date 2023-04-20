//
//  mocker.swift
//  demo-test
//
//  Created by David Frontegg on 19/04/2023.
//

import Foundation


struct Mocker {

    static func mock(name:String, body: [String: Any?]) async {
        
        var url = URL(string: "http://localhost:4001/mock/\(name)")
        var request = URLRequest(url: url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("http://localhost:4001", forHTTPHeaderField: "Origin")
        request.httpMethod = "POST"
        
        let json = try? JSONSerialization.data(withJSONObject: body)
        request.httpBody = json
        try? await URLSession.shared.data(for: request)
    }
}
