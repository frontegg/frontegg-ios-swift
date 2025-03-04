import Foundation

class DebugConfigurationChecker {

    private var baseUrl: String {
        return getBaseUrlFromFronteggPlist() ?? ""
    }

    private var appleAppSiteAssociationURL: String {
        return "\(baseUrl)/.well-known/apple-app-site-association"
    }

    private var oauthPreloginEndpoint: String {
        return "\(baseUrl)/oauth/prelogin"
    }

    func runChecks() {
        #if DEBUG
        print("🔍 Running IOS debug configuration checks...")

        let group = DispatchGroup()

        group.enter()
        validateAppleAppSiteAssociation {
            group.leave()
        }

        group.enter()
        checkRedirectURI { result in
            switch result {
            case .success:
                print("✅ Redirect URI check passed.")
            case .failure(let error):
                self.handleFatalError(error)
            }
            group.leave()
        }

        group.notify(queue: .main) {
            print("✅ All debug checks completed.")
        }
        
        #else
        print("ℹ️ Skipping debug checks in production.")
        completion()
        #endif
    }

    private func validateAppleAppSiteAssociation(completion: @escaping () -> Void) {
        guard let url = URL(string: appleAppSiteAssociationURL) else {
            print("Invalid `apple-app-site-association` URL.")
            completion()
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Failed to fetch `apple-app-site-association`: \(error.localizedDescription). Base URL might be incorrect.")
                completion()
                return
            }

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("Invalid response from `apple-app-site-association`.")
                completion()
                return
            }

            guard let data = data else {
                print("No data received from `apple-app-site-association`.")
                completion()
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let applinks = json["applinks"] as? [String: Any],
                   let details = applinks["details"] as? [[String: Any]] {
                    
                    let validAppIDs = details.compactMap { $0["appIDs"] as? [String] }.flatMap { $0 }
                    if validAppIDs.isEmpty {
                        print("❌ ERROR: `appIDs` missing in `apple-app-site-association`.")
                        completion()
                        return
                    }

                    print("✅ App site association validated successfully. App links are correctly configured.")
                } else {
                    print("❌ ERROR: `apple-app-site-association` missing required fields.")
                }
            } catch {
                print("JSON Parsing failed - \(error.localizedDescription)")
            }

            completion()
        }
        
        task.resume()
    }

    private func checkRedirectURI(completion: @escaping (Result<Void, DebugCheckError>) -> Void) {
        guard let clientId = getClientIdFromFronteggPlist() else {
            completion(.failure(.requestFailed("Failed to retrieve `clientId` from Frontegg.plist")))
            return
        }

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

        var urlComponents = URLComponents(string: oauthPreloginEndpoint)
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

    private func handleFatalError(_ error: DebugCheckError) {
        switch error {
        case .invalidRedirectURI(let statusCode, let response):
            fatalError("❌ ERROR: Redirect URI is invalid. Status: \(statusCode). Response: \(response)")
        case .requestFailed(let message):
            fatalError("❌ ERROR: Request failed - \(message)")
        case .invalidOAuthURL:
            fatalError("❌ ERROR: Failed to construct OAuth URL.")
        }
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
