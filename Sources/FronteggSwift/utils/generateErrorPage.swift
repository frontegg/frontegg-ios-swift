//
//  generateErrorPage.swift
//  
//
//  Created by David Frontegg on 13/09/2023.
//

import Foundation

func generateErrorPage(message:String, url:String, status: Int) -> String {
    return "<html lang=\"en\"><head><title>Fatal Error</title> <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no\" /> <style> body { display: flex; justify-content: center; margin: 2rem; flex-direction: column; font-family: -apple-system, BlinkMacSystemFont, Segoe UI, Helvetica, Arial, sans-serif, \"Apple Color Emoji\", \"Segoe UI Emoji\"; background-color: rgba(255, 100, 100, .05); } .title { font-size: 24px; color: red; font-weight: 600; margin-bottom: 2rem; } .message { color: #333; font-size: 16px; margin-top: 0.5rem; word-break: break-all; } </style></head><body><div class=\"title\">\(message)</div><div class=\"message\"><b>Status Code:</b>\(status)</div></body></html>"
}
