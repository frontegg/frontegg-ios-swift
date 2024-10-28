//
//  File.swift
//  
//
//  Created by David Antoon on 23/10/2024.
//

import Foundation


protocol WebAuthnCallbackData {}

@available(iOS 15.0, *)
extension WebauthnRegistration: WebAuthnCallbackData {}
@available(iOS 15.0, *)
extension WebauthnAssertion: WebAuthnCallbackData {}

extension Dictionary: WebAuthnCallbackData {}
