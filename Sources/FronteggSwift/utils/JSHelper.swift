//
//  JSHelper.swift
//  
//
//  Created by David Frontegg on 22/12/2022.
//

import Foundation
import WebKit

struct JSHelper {
    
    
    static func generateContextOptions(_ baseUrl: String, _ clientId: String) -> WKUserScript {
        
        let contextOptions = "window.contextOptions = {" +
        "baseUrl: \"\(baseUrl)\"," +
        "clientId: \"\(clientId)\"}"
        
        return WKUserScript(source: contextOptions, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
    }
    
    static func generatePreloadScript() -> WKUserScript {
        let preloadScriptUrl = Bundle.main.path(forResource: "preload-script", ofType: "js", inDirectory: "FronteggSwift_FronteggSwift.bundle")
        
        if let preloadScript = try? String(contentsOfFile: preloadScriptUrl!, encoding: String.Encoding.utf8) {
            
            return WKUserScript(source: preloadScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        }
        
        return WKUserScript(source: "", injectionTime: .atDocumentEnd, forMainFrameOnly: false)
    }
}
