//
//  FronteggWKContentController.swift
//  
//
//  Created by David Frontegg on 15/09/2023.
//

import Foundation
import WebKit


class FronteggWKContentController: NSObject, WKScriptMessageHandler{

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "fronteggNative" {
            if let functionName = message.body as? String {
                self.handleFunctionCall(functionName: functionName)
            }
        }
    }
    func handleFunctionCall(functionName: String) {
        switch functionName {
        case "showLoader":
            // Call your native function to show the loader
            FronteggAuth.shared.webLoading = true
        case "hideLoader":
            // Call your native function to show the loader
            FronteggAuth.shared.webLoading = false
        default:
            break
        }
    }

    func showNativeLoaderFunction() {
        // Your native implementation to show the loader
    }
    



}
