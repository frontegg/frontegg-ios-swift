import Foundation
import Network

class DebugConfigurationChecker {
    
    private func appleAppSiteAssociationURL(for baseUrl: String) -> String {
        return "\(baseUrl)/.well-known/apple-app-site-association"
    }
    
    private func oauthPreloginEndpoint(for baseUrl: String) -> String {
        return "\(baseUrl)/oauth/prelogin"
    }
    
    func runChecks() {
#if DEBUG
        print("🔍 Running IOS debug configuration checks...")
        
        let isAvailable = isInternetAvailableNow()
        
        if !isAvailable {
            print("❌ ERROR: No internet connection. Please connect to the internet to proceed with DEBUG checks.")
            return
        }
        
        let regions = getRegionsFromFronteggPlist()
        
        let group = DispatchGroup()
        
        if regions == nil {
            // Handle single region
            guard let clientId = getClientIdFromFronteggPlist(),
                  let baseUrl = getBaseUrlFromFronteggPlist() else {
                print("❌ ERROR: No clientId or baseUrl found in Frontegg.plist")
                return
            }
            
            if clientId.isEmpty || baseUrl.isEmpty {
                print("❌ ERROR: Empty clientId or baseUrl in Frontegg.plist")
                return
            }
            
            print("ℹ️ Running checks for single region configuration")
            
            group.enter()
            validateAppleAppSiteAssociation(baseUrl: baseUrl) {
                group.leave()
            }
            
            group.enter()
            checkRedirectURI(baseUrl: baseUrl, clientId: clientId) { result in
                switch result {
                case .success:
                    print("✅ Redirect URI check passed.")
                case .failure(let error):
                    self.handleFatalError(error, regionKey: nil)
                }
                group.leave()
            }
        } else {
            // Handle multi-region format
            let configuredRegions = regions!
            
            if configuredRegions.isEmpty {
                print("❌ ERROR: No valid regions found in Frontegg.plist")
                return
            }
            
            print("ℹ️ Found \(configuredRegions.count) region(s) to validate")
            
            for region in configuredRegions {
                print("🔍 Checking region: \(region.key)")
                
                group.enter()
                validateAppleAppSiteAssociation(baseUrl: region.baseUrl) {
                    group.leave()
                }
                
                group.enter()
                checkRedirectURI(baseUrl: region.baseUrl, clientId: region.clientId) { result in
                    switch result {
                    case .success:
                        print("✅ Redirect URI check passed for region: \(region.key)")
                    case .failure(let error):
                        self.handleFatalError(error, regionKey: region.key)
                    }
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            print("✅ All debug checks completed.")
        }
        
#else
        print("ℹ️ Skipping debug checks in production.")
#endif
    }
    
    private func validateAppleAppSiteAssociation(baseUrl: String, completion: @escaping () -> Void) {
        guard let url = URL(string: appleAppSiteAssociationURL(for: baseUrl)) else {
            print("❌ ERROR: Invalid `apple-app-site-association` URL for baseUrl: \(baseUrl)")
            completion()
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { completion() }
            
            if let error = error {
                print("❌ ERROR: Failed to fetch `apple-app-site-association`: \(error.localizedDescription). Base URL might be incorrect.")
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ ERROR: No HTTP response received for `apple-app-site-association`.")
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                print("❌ ERROR: Invalid response from `apple-app-site-association`. Status code: \(httpResponse.statusCode)")
                return
            }
            
            guard let data = data else {
                print("❌ ERROR: No data received from `apple-app-site-association`.")
                return
            }
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                      let applinks = json["applinks"] as? [String: Any],
                      let details = applinks["details"] as? [[String: Any]] else {
                    print("❌ ERROR: `apple-app-site-association` missing required fields.")
                    return
                }
                
                let validAppIDs = details.compactMap { $0["appIDs"] as? [String] }.flatMap { $0 }
                if validAppIDs.isEmpty {
                    print("❌ ERROR: `appIDs` missing in `apple-app-site-association`.")
                    return
                }
                
                print("✅ App site association validated successfully. App links are correctly configured.")
            } catch {
                print("❌ ERROR: JSON parsing failed - \(error.localizedDescription)")
            }
        }
        
        task.resume()
    }
    
    private func checkRedirectURI(baseUrl: String, clientId: String, completion: @escaping (Result<Void, DebugCheckError>) -> Void) {
        let baseRedirectUri = "com.frontegg.demo://\(baseUrl)/ios/oauth/callback"
        guard let encodedRedirectUri = baseRedirectUri
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            completion(.failure(.invalidOAuthURL))
            return
        }
        
        let state = UUID().uuidString
        let queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "redirect_uri", value: encodedRedirectUri)
        ]
        
        let oauthEndpoint = oauthPreloginEndpoint(for: baseUrl)
        var urlComponents = URLComponents(string: oauthEndpoint)
        urlComponents?.queryItems = queryItems
        
        guard let finalURL = urlComponents?.url else {
            completion(.failure(.invalidOAuthURL))
            return
        }
        
        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.requestFailed(error.localizedDescription)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.requestFailed("No HTTP response received.")))
                return
            }
            
            if httpResponse.statusCode != 200 {
                let errorMessage = String(data: data ?? Data(), encoding: .utf8) ?? "No response body"
                completion(.failure(.invalidRedirectURI(statusCode: httpResponse.statusCode, response: errorMessage)))
                return
            }
            
            completion(.success(()))
        }
        task.resume()
    }
    
    private func isInternetAvailableNow() -> Bool {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "NetworkCheck")
        var status = false

        let semaphore = DispatchSemaphore(value: 0)

        monitor.pathUpdateHandler = { path in
            status = (path.status == .satisfied)
            semaphore.signal()
        }

        monitor.start(queue: queue)

        semaphore.wait()
        monitor.cancel()

        return status
    }
    
    private func handleFatalError(_ error: DebugCheckError, regionKey: String?) {
        let regionInfo = regionKey.map { " for region \($0)" } ?? ""
        
        switch error {
        case .invalidRedirectURI(let statusCode, let response):
            print("❌ ERROR: Redirect URI is invalid\(regionInfo). Status: \(statusCode). Response: \(response)")
        case .requestFailed(let message):
            print("❌ ERROR: Request failed\(regionInfo) - \(message)")
        case .invalidOAuthURL:
            print("❌ ERROR: Failed to construct OAuth URL\(regionInfo).")
        }
    }
    
    private func getRegionsFromFronteggPlist() -> [(key: String, baseUrl: String, clientId: String)]? {
        guard let path = Bundle.main.path(forResource: "Frontegg", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path) else {
            print("❌ ERROR: Could not load Frontegg.plist")
            return nil
        }
        
        // Check if regions array exists (new multi-region format)
        guard let regionsArray = plist["regions"] as? [[String: Any]] else {
            return nil // No regions array found, fallback to legacy format
        }
        
        var regions: [(key: String, baseUrl: String, clientId: String)] = []
        
        for (index, regionDict) in regionsArray.enumerated() {
            guard let key = regionDict["key"] as? String,
                  let baseUrl = regionDict["baseUrl"] as? String,
                  let clientId = regionDict["clientId"] as? String else {
                print("❌ ERROR: Invalid region configuration at index \(index). Missing key, baseUrl, or clientId.")
                continue
            }
            
            if key.isEmpty || baseUrl.isEmpty || clientId.isEmpty {
                print("❌ ERROR: Empty values in region configuration at index \(index).")
                continue
            }
            
            regions.append((key: key, baseUrl: baseUrl, clientId: clientId))
            print("ℹ️ Loaded region: \(key) with baseUrl: \(baseUrl)")
        }
        
        return regions.isEmpty ? nil : regions
    }
    
    private func getClientIdFromFronteggPlist() -> String? {
        guard let path = Bundle.main.path(forResource: "Frontegg", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let clientId = plist["clientId"] as? String else {
            print("❌ ERROR: Could not load `clientId` from Frontegg.plist")
            return nil
        }
        return clientId
    }
    
    private func getBaseUrlFromFronteggPlist() -> String? {
        guard let path = Bundle.main.path(forResource: "Frontegg", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let baseUrl = plist["baseUrl"] as? String else {
            print("❌ ERROR: Could not load `baseUrl` from Frontegg.plist")
            return nil
        }
        return baseUrl
    }
    
    enum DebugCheckError: Error {
        case invalidRedirectURI(statusCode: Int, response: String)
        case requestFailed(String)
        case invalidOAuthURL
    }
}
