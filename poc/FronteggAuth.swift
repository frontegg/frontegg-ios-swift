//
//  Frontegg.swift
//  poc
//
//  Created by David Frontegg on 11/11/2022.
//

import Foundation



final class FronteggAuth {
    
    
}



//public func authentication(session: URLSession = .shared, bundle: Bundle = .main) -> Authentication {
//    let values = plistValues(bundle: bundle)!
//    return authentication(clientId: values.clientId, domain: values.domain, session: session)
//}
//



func plistValues(bundle: Bundle) -> (clientId: String, domain: String)? {
    guard let path = bundle.path(forResource: "Auth0", ofType: "plist"),
          let values = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            print("Missing Auth0.plist file with 'ClientId' and 'Domain' entries in main bundle!")
            return nil
        }

    guard let clientId = values["ClientId"] as? String, let domain = values["Domain"] as? String else {
            print("Auth0.plist file at \(path) is missing 'ClientId' and/or 'Domain' entries!")
            print("File currently has the following entries: \(values)")
            return nil
        }
    return (clientId: clientId, domain: domain)
}
