//
//  NoRedirectSessionDelegate.swift
//  
//
//  Created by David Frontegg on 24/10/2023.
//

import Foundation


class NoRedirectSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Returning nil will prevent the redirect
        completionHandler(nil)
    }
}
