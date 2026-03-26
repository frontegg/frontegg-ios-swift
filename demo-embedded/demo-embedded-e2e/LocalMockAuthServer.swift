import Foundation
import Network

final class LocalMockAuthServer {
    private let readinessTimeout: TimeInterval = 10
    private let listenerQueue = DispatchQueue(label: "com.frontegg.demo-embedded-e2e.mock-server")
    private let state = MockAuthState()
    private let requestLogLock = NSLock()
    private var requestLog: [LoggedRequest] = []
    private let port: UInt16 = 49381
    private var listener: NWListener?

    let clientId = "demo-embedded-e2e-client"
    let baseURL = URL(string: "http://127.0.0.1:49381")!

    init() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let port = NWEndpoint.Port(rawValue: port)!
        let listener = try NWListener(using: parameters, on: port)
        self.listener = listener

        let startupSemaphore = DispatchSemaphore(value: 0)
        let startupLock = NSLock()
        var startupCompleted = false
        var startupError: Error?

        listener.stateUpdateHandler = { state in
            startupLock.lock()
            defer { startupLock.unlock() }

            guard !startupCompleted else { return }

            switch state {
            case .ready:
                startupCompleted = true
                startupSemaphore.signal()
            case .failed(let error):
                startupCompleted = true
                startupError = error
                startupSemaphore.signal()
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }

        listener.start(queue: listenerQueue)

        let result = startupSemaphore.wait(timeout: .now() + readinessTimeout)
        if result == .timedOut {
            listener.cancel()
            throw NSError(
                domain: "LocalMockAuthServer",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Mock auth server did not become ready at \(baseURL.absoluteString)"]
            )
        }

        if let startupError {
            listener.cancel()
            throw startupError
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    func launchEnvironment(
        resetState: Bool,
        useTestingWebAuthenticationTransport: Bool = true,
        forceNetworkPathOffline: Bool = false
    ) -> [String: String] {
        [
            "frontegg-testing": "true",
            "FRONTEGG_E2E_BASE_URL": baseURL.absoluteString,
            "FRONTEGG_E2E_CLIENT_ID": clientId,
            "FRONTEGG_E2E_RESET_STATE": resetState ? "1" : "0",
            "FRONTEGG_E2E_FORCE_NETWORK_PATH_OFFLINE": forceNetworkPathOffline ? "1" : "0",
            "FRONTEGG_TEST_WEB_AUTH_TRANSPORT": useTestingWebAuthenticationTransport ? "1" : "0",
            "FRONTEGG_TEST_SOCIAL_AUTHORIZE_URL_GOOGLE": "\(baseURL.absoluteString)/idp/google/authorize",
        ]
    }

    func reset() throws {
        state.reset()
        requestLogLock.lock()
        requestLog.removeAll()
        requestLogLock.unlock()
    }

    func enqueue(
        method: String = "GET",
        path: String,
        responses: [[String: Any]]
    ) throws {
        state.enqueue(method: method, path: path, responses: responses)
    }

    func queueProbeFailures(statusCodes: [Int]) throws {
        try enqueue(
            method: "HEAD",
            path: "/test",
            responses: statusCodes.map { ["status": $0, "body": "offline"] }
        )
    }

    func waitForRequest(
        method: String? = nil,
        path: String,
        timeout: TimeInterval = 10
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if hasRequest(method: method, path: path) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return hasRequest(method: method, path: path)
    }

    func requestCount(path: String) -> Int {
        requestLogLock.lock()
        defer { requestLogLock.unlock() }
        return requestLog.filter { $0.path == path }.count
    }

    private func handle(connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveRequest(on: connection, buffer: Data())
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: listenerQueue)
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var accumulated = buffer
            if let data {
                accumulated.append(data)
            }

            if let request = self.parseRequest(from: accumulated) {
                let response = self.route(request)
                self.send(response, for: request, on: connection)
                return
            }

            if isComplete || error != nil {
                connection.cancel()
                return
            }

            self.receiveRequest(on: connection, buffer: accumulated)
        }
    }

    private func parseRequest(from buffer: Data) -> HTTPRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = buffer.range(of: separator) else {
            return nil
        }

        let headerData = buffer.subdata(in: 0..<headerRange.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return nil
        }

        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count >= 2 else {
            return nil
        }

        let method = String(requestParts[0]).uppercased()
        let target = String(requestParts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separatorIndex = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = String(line[line.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name] = value
        }

        let bodyStart = headerRange.upperBound
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        guard buffer.count >= bodyStart + contentLength else {
            return nil
        }

        let body = buffer.subdata(in: bodyStart..<(bodyStart + contentLength))
        let targetURLString = target.hasPrefix("http") ? target : "http://127.0.0.1\(target)"
        let components = URLComponents(string: targetURLString)
        let path = normalizePath(components?.path ?? "/")

        var query: [String: [String]] = [:]
        for item in components?.queryItems ?? [] {
            query[item.name, default: []].append(item.value ?? "")
        }

        return HTTPRequest(
            method: method,
            target: target,
            path: path,
            query: query,
            headers: headers,
            body: body
        )
    }

    private func route(_ request: HTTPRequest) -> HTTPResponse {
        log(request)
        if let queued = state.dequeue(method: request.method, path: request.path) {
            return queuedResponse(from: queued)
        }

        switch (request.method, request.path) {
        case ("HEAD", "/test"), ("GET", "/test"):
            return textResponse(status: 200, body: "ok")
        case ("GET", "/oauth/authorize"):
            return renderAuthorizePage(query: request.query)
        case ("GET", "/oauth/account/social/success"):
            return handleSocialLoginSuccess(query: request.query)
        case ("GET", "/oauth/prelogin"):
            return handleHostedPrelogin(query: request.query)
        case ("POST", "/oauth/postlogin"):
            return handleHostedPostlogin(request)
        case ("GET", "/oauth/postlogin/redirect"):
            return handleHostedPostloginRedirect(query: request.query)
        case ("GET", "/idp/google/authorize"):
            return handleMockGoogleAuthorize(query: request.query)
        case ("GET", "/embedded/continue"):
            return renderEmbeddedContinue(query: request.query)
        case ("POST", "/embedded/password"):
            return completeEmbeddedPassword(request)
        case ("GET", "/browser/complete"):
            return completeBrowserFlow(query: request.query)
        case ("GET", "/dashboard"):
            return handleDashboard()
        case ("POST", "/oauth/token"):
            return handleOAuthToken(request)
        case ("POST", "/frontegg/oauth/authorize/silent"):
            return handleSilentAuthorize(request)
        case ("GET", "/flags"):
            return handleFeatureFlags()
        case ("GET", "/frontegg/flags"):
            return handleFeatureFlags()
        case ("GET", "/frontegg/metadata"):
            return handleMetadata()
        case ("GET", "/vendors/public"), ("GET", "/frontegg/vendors/public"):
            return handlePublicVendors()
        case ("GET", "/frontegg/identity/resources/sso/v2"):
            return handleSocialLoginConfig()
        case ("GET", "/frontegg/identity/resources/configurations/v1/public"):
            return handlePublicConfiguration()
        case ("GET", "/frontegg/identity/resources/configurations/v1/auth/strategies/public"):
            return handleAuthStrategies()
        case ("GET", "/frontegg/identity/resources/configurations/v1/sign-up/strategies"):
            return handleSignUpStrategies()
        case ("GET", "/frontegg/team/resources/sso/v2/configurations/public"):
            return handleTeamSSOConfigurations()
        case ("GET", "/identity/resources/sso/custom/v1"):
            return handleCustomSocialLoginConfig()
        case ("GET", "/frontegg/identity/resources/sso/custom/v1"):
            return handleCustomSocialLoginConfig()
        case ("GET", "/identity/resources/configurations/sessions/v1"):
            return handleSessionConfiguration()
        case ("GET", "/frontegg/identity/resources/configurations/v1/captcha-policy/public"):
            return handleCaptchaPolicy()
        case ("POST", "/frontegg/identity/resources/auth/v1/user/token/refresh"):
            return handleHostedRefresh(request)
        case ("POST", "/frontegg/identity/resources/auth/v2/user/sso/prelogin"):
            return handleHostedSSOPrelogin(request)
        case ("POST", "/frontegg/identity/resources/auth/v1/user"):
            return handleHostedPasswordLogin(request)
        case ("GET", "/identity/resources/users/v2/me"):
            return handleMe(request)
        case ("GET", "/identity/resources/users/v3/me/tenants"):
            return handleTenants(request)
        case ("POST", "/oauth/logout/token"):
            return handleLogout(request)
        default:
            return jsonResponse(status: 404, payload: ["error": "Unhandled route \(request.method) \(request.path)"])
        }
    }

    private func renderAuthorizePage(query: [String: [String]]) -> HTTPResponse {
        let redirectURI = firstValue(query, key: "redirect_uri")
        let stateValue = firstValue(query, key: "state")
        let clientId = firstValue(query, key: "client_id")
        let loginAction = firstValue(query, key: "login_direct_action")
        let loginHint = firstValue(query, key: "login_hint")

        if !loginAction.isEmpty {
            let decodedAction = decodeBase64URLJSON(loginAction) ?? [:]
            let destination = decodedAction["data"] as? String ?? ""

            let title: String
            let buttonTitle: String
            let email: String

            if destination.contains("custom-sso") {
                title = "Custom SSO Mock Server"
                buttonTitle = "Continue to Custom SSO"
                email = "custom-sso@frontegg.com"
            } else if destination.contains("mock-social-provider") {
                title = "Mock Social Login"
                buttonTitle = "Continue with Mock Social"
                email = "social-login@frontegg.com"
            } else {
                title = "Direct Login Mock Server"
                buttonTitle = "Continue"
                email = "direct-login@frontegg.com"
            }

            let body = """
            <h1>\(htmlEscaped(title))</h1>
            <form action="/browser/complete" method="get">
              <input type="hidden" name="email" value="\(htmlEscaped(email))" />
              <input type="hidden" name="redirect_uri" value="\(htmlEscaped(redirectURI))" />
              <input type="hidden" name="state" value="\(htmlEscaped(stateValue))" />
              <button type="submit">\(htmlEscaped(buttonTitle))</button>
            </form>
            """

            return htmlResponse(status: 200, title: title, body: body)
        }

        let hostedState = state.issueHostedLoginContext(
            redirectURI: redirectURI,
            originalState: stateValue,
            loginHint: loginHint
        )

        var components = URLComponents(url: baseURL.appendingPathComponent("oauth/prelogin"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: hostedState),
        ]
        if !loginHint.isEmpty {
            components?.queryItems?.append(URLQueryItem(name: "login_hint", value: loginHint))
        }

        return redirectResponse(location: components?.string ?? "\(baseURL.absoluteString)/oauth/prelogin?state=\(hostedState)")
    }

    private func handleHostedPrelogin(query: [String: [String]]) -> HTTPResponse {
        let hostedState = firstValue(query, key: "state")
        guard let context = state.hostedLoginContext(for: hostedState) else {
            return htmlResponse(status: 400, title: "Invalid hosted flow", body: "<h1>Invalid hosted flow</h1>")
        }

        let email = firstValue(query, key: "email", default: context.loginHint)
        if email.isEmpty {
            return renderHostedEmailStep(hostedState: hostedState)
        }

        if email.hasSuffix("@saml-domain.com") {
            return renderHostedProviderStep(
                title: "OKTA SAML Mock Server",
                buttonTitle: "Login With Okta",
                hostedState: hostedState,
                email: email
            )
        }

        if email.hasSuffix("@oidc-domain.com") {
            return renderHostedProviderStep(
                title: "OKTA OIDC Mock Server",
                buttonTitle: "Login With Okta",
                hostedState: hostedState,
                email: email
            )
        }

        return renderHostedPasswordStep(
            hostedState: hostedState,
            email: email,
            prefilledPassword: !context.loginHint.isEmpty
        )
    }

    private func renderHostedEmailStep(hostedState: String) -> HTTPResponse {
        let body = """
        <h1>Mock Embedded Login</h1>
        <form action="/oauth/prelogin" method="get">
          <input type="hidden" name="state" value="\(htmlEscaped(hostedState))" />
          <input type="email" name="email" placeholder="Email is required" />
          <button type="submit">Continue</button>
        </form>
        <form action="/__frontegg_test/social-login" method="get">
          <input type="hidden" name="provider" value="google" />
          <button type="submit">Continue with Mock Google</button>
        </form>
        \(hostedBootstrapScript(includeRefreshAttempt: true))
        """

        return htmlResponse(status: 200, title: "Mock Embedded Login", body: body)
    }

    private func renderHostedPasswordStep(
        hostedState: String,
        email: String,
        prefilledPassword: Bool
    ) -> HTTPResponse {
        let passwordValue = prefilledPassword ? #" value="Testpassword1!""# : ""
        let hostedStateLiteral = javaScriptLiteral(hostedState)
        let emailLiteral = javaScriptLiteral(email)
        let autoSubmitScript = prefilledPassword
            ? """
              window.addEventListener('load', () => {
                setTimeout(() => {
                  if (passwordField.value) {
                    form.requestSubmit();
                  }
                }, 0);
              });
              """
            : ""
        let body = """
        <h1>Password Login</h1>
        <form id="password-login-form">
          <input id="hosted-email" type="email" name="email" placeholder="Email is required" value="\(htmlEscaped(email))" />
          <input id="hosted-password" type="password" name="password" placeholder="Password is required"\(passwordValue) />
          <button type="submit">Sign in</button>
          <p id="status-message"></p>
        </form>
        <script>
          \(hostedBootstrapScript(includeRefreshAttempt: true))
          const hostedState = \(hostedStateLiteral);
          const defaultEmail = \(emailLiteral);
          const form = document.getElementById('password-login-form');
          const emailField = document.getElementById('hosted-email');
          const passwordField = document.getElementById('hosted-password');
          const statusMessage = document.getElementById('status-message');

          form.addEventListener('submit', async (event) => {
            event.preventDefault();
            const email = emailField.value || defaultEmail;
            try {
              await fetch('/frontegg/identity/resources/auth/v2/user/sso/prelogin', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ email })
              }).catch(() => null);

              const authResponse = await fetch('/frontegg/identity/resources/auth/v1/user', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                  email,
                  password: passwordField.value,
                  invitationToken: ''
                })
              });
              if (!authResponse.ok) {
                throw new Error('auth_failed');
              }
              const authData = await authResponse.json();
              await fetch('/identity/resources/configurations/sessions/v1').catch(() => null);
              const postloginResponse = await fetch('/oauth/postlogin', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                  state: hostedState,
                  token: authData.access_token
                })
              });
              if (!postloginResponse.ok) {
                throw new Error('postlogin_failed');
              }
              await postloginResponse.json();
              window.location.assign('/oauth/postlogin/redirect?state=' + encodeURIComponent(hostedState));
            } catch (error) {
              statusMessage.textContent = 'Sign in failed';
            }
          });
          \(autoSubmitScript)
        </script>
        """

        return htmlResponse(status: 200, title: "Password Login", body: body)
    }

    private func renderHostedProviderStep(
        title: String,
        buttonTitle: String,
        hostedState: String,
        email: String
    ) -> HTTPResponse {
        let hostedStateLiteral = javaScriptLiteral(hostedState)
        let emailLiteral = javaScriptLiteral(email)
        let accessTokenLiteral = javaScriptLiteral(accessToken(email: email))
        let body = """
        <h1>\(htmlEscaped(title))</h1>
        <form id="provider-login-form">
          <button type="submit">\(htmlEscaped(buttonTitle))</button>
          <p id="provider-status"></p>
        </form>
        <script>
          \(hostedBootstrapScript(includeRefreshAttempt: true))
          const hostedState = \(hostedStateLiteral);
          const email = \(emailLiteral);
          const accessToken = \(accessTokenLiteral);
          const form = document.getElementById('provider-login-form');
          const statusMessage = document.getElementById('provider-status');

          form.addEventListener('submit', async (event) => {
            event.preventDefault();
            try {
              const preloginResponse = await fetch('/frontegg/identity/resources/auth/v2/user/sso/prelogin', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ email })
              });
              if (!preloginResponse.ok) {
                throw new Error('sso_prelogin_failed');
              }
              const postloginResponse = await fetch('/oauth/postlogin', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                  state: hostedState,
                  token: accessToken
                })
              });
              if (!postloginResponse.ok) {
                throw new Error('postlogin_failed');
              }
              await postloginResponse.json();
              window.location.assign('/oauth/postlogin/redirect?state=' + encodeURIComponent(hostedState));
            } catch (error) {
              statusMessage.textContent = 'Login failed';
            }
          });
        </script>
        """

        return htmlResponse(status: 200, title: title, body: body)
    }

    private func hostedBootstrapScript(includeRefreshAttempt: Bool) -> String {
        let bootstrapURLs = [
            "/vendors/public",
            "/frontegg/metadata",
            "/flags",
            "/frontegg/flags",
            "/frontegg/identity/resources/sso/v2",
            "/frontegg/identity/resources/configurations/v1/public",
            "/frontegg/identity/resources/configurations/v1/auth/strategies/public",
            "/frontegg/identity/resources/configurations/v1/sign-up/strategies",
            "/frontegg/team/resources/sso/v2/configurations/public",
            "/frontegg/vendors/public",
            "/frontegg/identity/resources/sso/custom/v1",
            "/frontegg/identity/resources/configurations/v1/captcha-policy/public",
        ]
        let bootstrapList = bootstrapURLs
            .map { "fetch(\(javaScriptLiteral($0))).catch(() => null)" }
            .joined(separator: ",\n            ")

        let refreshCall = includeRefreshAttempt
            ? """
                fetch('/frontegg/identity/resources/auth/v1/user/token/refresh', {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json' },
                  body: '{}'
                }).catch(() => null),
            """
            : ""

        return """
        window.addEventListener('load', () => {
          Promise.allSettled([
            \(refreshCall)
            \(bootstrapList)
          ]);
        });
        """
    }

    private func renderEmbeddedContinue(query: [String: [String]]) -> HTTPResponse {
        let email = firstValue(query, key: "email", default: "test@frontegg.com")
        let redirectURI = firstValue(query, key: "redirect_uri")
        let stateValue = firstValue(query, key: "state")
        return renderEmbeddedContinue(
            email: email,
            redirectURI: redirectURI,
            stateValue: stateValue,
            prefilledPassword: false
        )
    }

    private func renderEmbeddedContinue(
        email: String,
        redirectURI: String,
        stateValue: String,
        prefilledPassword: Bool
    ) -> HTTPResponse {

        if email.hasSuffix("@saml-domain.com") {
            let body = """
            <h1>OKTA SAML Mock Server</h1>
            <form action="/browser/complete" method="get">
              <input type="hidden" name="email" value="\(htmlEscaped(email))" />
              <input type="hidden" name="redirect_uri" value="\(htmlEscaped(redirectURI))" />
              <input type="hidden" name="state" value="\(htmlEscaped(stateValue))" />
              <button type="submit">Login With Okta</button>
            </form>
            """
            return htmlResponse(status: 200, title: "OKTA SAML Mock Server", body: body)
        }

        if email.hasSuffix("@oidc-domain.com") {
            let body = """
            <h1>OKTA OIDC Mock Server</h1>
            <form action="/browser/complete" method="get">
              <input type="hidden" name="email" value="\(htmlEscaped(email))" />
              <input type="hidden" name="redirect_uri" value="\(htmlEscaped(redirectURI))" />
              <input type="hidden" name="state" value="\(htmlEscaped(stateValue))" />
              <button type="submit">Login With Okta</button>
            </form>
            """
            return htmlResponse(status: 200, title: "OKTA OIDC Mock Server", body: body)
        }

        let passwordValue = prefilledPassword ? #" value="Testpassword1!""# : ""
        let body = """
        <h1>Password Login</h1>
        <form action="/embedded/password" method="post">
          <input type="hidden" name="email" value="\(htmlEscaped(email))" />
          <input type="hidden" name="redirect_uri" value="\(htmlEscaped(redirectURI))" />
          <input type="hidden" name="state" value="\(htmlEscaped(stateValue))" />
          <input type="password" name="password" placeholder="Password is required"\(passwordValue) />
          <button type="submit">Sign in</button>
        </form>
        """
        return htmlResponse(status: 200, title: "Password Login", body: body)
    }

    private func completeEmbeddedPassword(_ request: HTTPRequest) -> HTTPResponse {
        let form = parseURLEncodedForm(data: request.body)
        let email = form["email"] ?? "test@frontegg.com"
        let redirectURI = form["redirect_uri"] ?? ""
        let stateValue = form["state"] ?? ""
        let code = state.issueCode(email: email, redirectURI: redirectURI, state: stateValue)
        return redirectResponse(location: buildCallbackURL(redirectURI: redirectURI, code: code, state: stateValue))
    }

    private func completeBrowserFlow(query: [String: [String]]) -> HTTPResponse {
        let email = firstValue(query, key: "email", default: "browser@frontegg.com")
        let redirectURI = firstValue(query, key: "redirect_uri")
        let stateValue = firstValue(query, key: "state")
        let code = state.issueCode(email: email, redirectURI: redirectURI, state: stateValue)
        return redirectResponse(location: buildCallbackURL(redirectURI: redirectURI, code: code, state: stateValue))
    }

    private func handleOAuthToken(_ request: HTTPRequest) -> HTTPResponse {
        let body = parseJSONDictionary(request.body)
        let grantType = body["grant_type"] as? String ?? ""

        switch grantType {
        case "authorization_code":
            guard let code = body["code"] as? String, !code.isEmpty else {
                return jsonResponse(status: 400, payload: ["error": "missing_code"])
            }
            guard let authCode = state.consumeCode(code) else {
                return jsonResponse(status: 400, payload: ["error": "invalid_code"])
            }
            let refreshToken = "refresh-\(UUID().uuidString.lowercased())"
            state.saveRefreshToken(refreshToken, email: authCode.email)
            return jsonResponse(status: 200, payload: authResponse(email: authCode.email, refreshToken: refreshToken))

        case "refresh_token":
            guard let refreshToken = body["refresh_token"] as? String, !refreshToken.isEmpty else {
                return jsonResponse(status: 400, payload: ["error": "missing_refresh_token"])
            }
            guard let email = state.email(forRefreshToken: refreshToken) else {
                return jsonResponse(status: 401, payload: ["error": "invalid_refresh_token"])
            }
            return jsonResponse(status: 200, payload: authResponse(email: email, refreshToken: refreshToken))

        default:
            return jsonResponse(status: 400, payload: ["error": "unsupported_grant_type \(grantType)"])
        }
    }

    private func handleSilentAuthorize(_ request: HTTPRequest) -> HTTPResponse {
        guard let refreshToken = refreshTokenFromCookies(request.headers["cookie"]),
              let email = state.email(forRefreshToken: refreshToken) else {
            return jsonResponse(status: 401, payload: ["error": "invalid_refresh_cookie"])
        }

        return jsonResponse(status: 200, payload: authResponse(email: email, refreshToken: refreshToken))
    }

    private func handleFeatureFlags() -> HTTPResponse {
        jsonResponse(status: 200, payload: [
            "mobile-enable-logging": "off",
        ])
    }

    private func handleMetadata() -> HTTPResponse {
        jsonResponse(status: 200, payload: [
            "appName": "demo-embedded-e2e",
            "environment": "local",
        ])
    }

    private func handlePublicVendors() -> HTTPResponse {
        jsonResponse(status: 200, payload: [
            "vendors": [],
        ])
    }

    private func handleSocialLoginConfig() -> HTTPResponse {
        jsonResponse(status: 200, payload: [
            [
                "type": "google",
                "active": true,
                "customised": false,
                "clientId": "mock-google-client-id",
                "redirectUrl": "\(baseURL.absoluteString)/oauth/account/social/success",
                "redirectUrlPattern": "\(baseURL.absoluteString)/oauth/account/social/success",
                "options": [
                    "verifyEmail": false,
                ],
                "additionalScopes": [],
            ],
        ])
    }

    private func handleCustomSocialLoginConfig() -> HTTPResponse {
        jsonResponse(status: 200, payload: [
            "providers": [],
        ])
    }

    private func handlePublicConfiguration() -> HTTPResponse {
        jsonResponse(status: 200, payload: [
            "embeddedMode": true,
            "loginBoxVisible": true,
        ])
    }

    private func handleAuthStrategies() -> HTTPResponse {
        jsonResponse(status: 200, payload: [
            "password": true,
            "socialLogin": true,
            "sso": true,
        ])
    }

    private func handleSignUpStrategies() -> HTTPResponse {
        jsonResponse(status: 200, payload: [
            "allowSignUp": true,
        ])
    }

    private func handleTeamSSOConfigurations() -> HTTPResponse {
        jsonResponse(status: 200, payload: [])
    }

    private func handleSessionConfiguration() -> HTTPResponse {
        jsonResponse(status: 200, payload: [
            "cookieName": "fe_refresh_demo_embedded_e2e",
            "keepSessionAlive": true,
        ])
    }

    private func handleCaptchaPolicy() -> HTTPResponse {
        jsonResponse(status: 200, payload: [
            "enabled": false,
        ])
    }

    private func handleHostedRefresh(_ request: HTTPRequest) -> HTTPResponse {
        guard let refreshToken = refreshTokenFromCookies(request.headers["cookie"]),
              let email = state.email(forRefreshToken: refreshToken) else {
            return jsonResponse(status: 401, payload: [
                "errors": ["Session not found"],
            ])
        }

        return jsonResponse(status: 200, payload: authResponse(email: email, refreshToken: refreshToken))
    }

    private func handleHostedSSOPrelogin(_ request: HTTPRequest) -> HTTPResponse {
        let body = parseJSONDictionary(request.body)
        let email = (body["email"] as? String ?? "").lowercased()

        if email.hasSuffix("@saml-domain.com") {
            return jsonResponse(status: 200, payload: [
                "type": "saml",
                "tenantId": tenantId(for: email),
            ])
        }

        if email.hasSuffix("@oidc-domain.com") {
            return jsonResponse(status: 200, payload: [
                "type": "oidc",
                "tenantId": tenantId(for: email),
            ])
        }

        return jsonResponse(status: 404, payload: [
            "errors": ["SSO domain was not found"],
        ])
    }

    private func handleHostedPasswordLogin(_ request: HTTPRequest) -> HTTPResponse {
        let body = parseJSONDictionary(request.body)
        let email = body["email"] as? String ?? "test@frontegg.com"
        let refreshToken = "refresh-\(UUID().uuidString.lowercased())"
        state.saveRefreshToken(refreshToken, email: email)

        let authData = (try? JSONSerialization.data(withJSONObject: authResponse(email: email, refreshToken: refreshToken))) ?? Data("{}".utf8)
        let cookieValue = "fe_refresh_demo_embedded_e2e=\(refreshToken); Path=/; HttpOnly; SameSite=Lax"
        return HTTPResponse(
            statusCode: 200,
            headers: [
                "Content-Type": "application/json; charset=utf-8",
                "Set-Cookie": cookieValue,
            ],
            body: authData
        )
    }

    private func handleHostedPostlogin(_ request: HTTPRequest) -> HTTPResponse {
        let body = parseJSONDictionary(request.body)
        let hostedState = body["state"] as? String ?? ""
        guard let context = state.hostedLoginContext(for: hostedState) else {
            return jsonResponse(status: 400, payload: [
                "error": "invalid_state",
            ])
        }

        let email: String
        if let token = body["token"] as? String,
           let resolvedEmail = emailFromBearerToken(token) {
            email = resolvedEmail
        } else if !context.loginHint.isEmpty {
            email = context.loginHint
        } else {
            return jsonResponse(status: 400, payload: [
                "error": "missing_token",
            ])
        }

        let code = state.issueCode(email: email, redirectURI: context.redirectURI, state: context.originalState)
        let redirectURL = buildCallbackURL(
            redirectURI: context.redirectURI,
            code: code,
            state: context.originalState
        )
        state.recordHostedPostloginCompletion(hostedState: hostedState, email: email)
        return jsonResponse(status: 200, payload: [
            "redirectUrl": redirectURL,
        ])
    }

    private func handleHostedPostloginRedirect(query: [String: [String]]) -> HTTPResponse {
        let hostedState = firstValue(query, key: "state")
        guard let context = state.hostedLoginContext(for: hostedState),
              let email = state.completedHostedLoginEmail(for: hostedState) else {
            return jsonResponse(status: 400, payload: [
                "error": "missing_postlogin_completion",
            ])
        }

        let code = state.issueCode(email: email, redirectURI: context.redirectURI, state: context.originalState)
        return redirectResponse(location: buildCallbackURL(
            redirectURI: context.redirectURI,
            code: code,
            state: context.originalState
        ))
    }

    private func handleMockGoogleAuthorize(query: [String: [String]]) -> HTTPResponse {
        let redirectURI = firstValue(query, key: "redirect_uri")
        let stateValue = firstValue(query, key: "state")
        guard !redirectURI.isEmpty, !stateValue.isEmpty else {
            return htmlResponse(status: 400, title: "Invalid mock Google request", body: "<h1>Invalid mock Google request</h1>")
        }

        let email = "google-social@frontegg.com"
        let code = state.issueCode(email: email, redirectURI: redirectURI, state: stateValue)
        let body = """
        <h1>Mock Google Login</h1>
        <p>Fake Google account: \(htmlEscaped(email))</p>
        <form action="\(htmlEscaped(redirectURI))" method="get">
          <input type="hidden" name="code" value="\(htmlEscaped(code))" />
          <input type="hidden" name="state" value="\(htmlEscaped(stateValue))" />
          <button type="submit">Continue with Mock Google</button>
        </form>
        """

        return htmlResponse(status: 200, title: "Mock Google Login", body: body)
    }

    private func handleSocialLoginSuccess(query: [String: [String]]) -> HTTPResponse {
        let code = firstValue(query, key: "code")
        let rawState = firstValue(query, key: "state")
        guard let authCode = state.authCode(for: code) else {
            return jsonResponse(status: 400, payload: ["error": "invalid_social_code"])
        }

        // First pass: provider redirected back to Frontegg inside ASWebAuthenticationSession.
        // Redirect to the app callback URL so the session can close and the SDK can normalize
        // the callback back into /oauth/account/social/success inside the embedded webview.
        if firstValue(query, key: "redirectUri").isEmpty {
            guard let socialState = decodeSocialState(rawState),
                  let bundleId = socialState["bundleId"] as? String,
                  !bundleId.isEmpty else {
                return jsonResponse(status: 400, payload: ["error": "invalid_social_state"])
            }

            var callbackComponents = URLComponents()
            callbackComponents.scheme = bundleId.lowercased()
            callbackComponents.host = baseURL.host
            callbackComponents.path = "/oauth/account/redirect/ios/\(bundleId)/google"
            callbackComponents.queryItems = [
                URLQueryItem(name: "code", value: code),
                URLQueryItem(name: "state", value: rawState),
            ]

            return redirectResponse(location: callbackComponents.string ?? "")
        }

        // Second pass: embedded webview loads /oauth/account/social/success after callback
        // normalization. Redirect to the generated embedded redirect URI with code and state,
        // so the webview handles the hosted callback directly using the same path shape that
        // SocialLoginUrlGenerator produces.
        let redirectURI = firstValue(query, key: "redirectUri")
        guard !redirectURI.isEmpty else {
            return jsonResponse(status: 400, payload: ["error": "missing_social_redirect_uri"])
        }

        return redirectResponse(
            location: buildCallbackURL(
                redirectURI: redirectURI,
                code: code,
                state: rawState
            )
        )
    }

    private func handleDashboard() -> HTTPResponse {
        htmlResponse(status: 200, title: "Dashboard", body: "<h1>Dashboard</h1>")
    }

    private func handleMe(_ request: HTTPRequest) -> HTTPResponse {
        guard let email = emailFromAuthorizationHeader(request.headers["authorization"]) else {
            return jsonResponse(status: 401, payload: ["error": "missing_access_token"])
        }

        return jsonResponse(status: 200, payload: userResponse(email: email))
    }

    private func handleTenants(_ request: HTTPRequest) -> HTTPResponse {
        guard let email = emailFromAuthorizationHeader(request.headers["authorization"]) else {
            return jsonResponse(status: 401, payload: ["error": "missing_access_token"])
        }

        let tenant = tenantResponse(email: email)
        return jsonResponse(status: 200, payload: [
            "tenants": [tenant],
            "activeTenant": tenant,
        ])
    }

    private func handleLogout(_ request: HTTPRequest) -> HTTPResponse {
        if let refreshToken = refreshTokenFromCookies(request.headers["cookie"]) {
            state.invalidateRefreshToken(refreshToken)
        }

        return jsonResponse(status: 200, payload: ["ok": true])
    }

    private func send(_ response: HTTPResponse, for request: HTTPRequest, on connection: NWConnection) {
        let transmit = { [self] in
            if response.closeConnection {
                connection.cancel()
                return
            }

            var headers = response.headers
            headers["Connection"] = "close"
            headers["Content-Length"] = headers["Content-Length"] ?? "\(response.body.count)"

            var payload = Data()
            let statusLine = "HTTP/1.1 \(response.statusCode) \(reasonPhrase(for: response.statusCode))\r\n"
            payload.append(statusLine.data(using: .utf8)!)

            for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
                let headerLine = "\(key): \(value)\r\n"
                payload.append(headerLine.data(using: .utf8)!)
            }
            payload.append(Data("\r\n".utf8))

            if request.method != "HEAD" && !response.body.isEmpty {
                payload.append(response.body)
            }

            connection.send(content: payload, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }

        if response.delayMs > 0 {
            listenerQueue.asyncAfter(deadline: .now() + .milliseconds(response.delayMs), execute: transmit)
        } else {
            listenerQueue.async(execute: transmit)
        }
    }

    private func queuedResponse(from spec: [String: Any]) -> HTTPResponse {
        let delayMs = intValue(spec["delay_ms"])
        let closeConnection = boolValue(spec["close_connection"])
        var statusCode = intValue(spec["status"], default: 200)

        var headers: [String: String] = [:]
        if let rawHeaders = spec["headers"] as? [String: String] {
            headers = rawHeaders
        } else if let rawHeaders = spec["headers"] as? [String: Any] {
            for (key, value) in rawHeaders {
                headers[key] = String(describing: value)
            }
        }

        if let redirect = spec["redirect"] as? String, !redirect.isEmpty {
            headers["Location"] = redirect
            if spec["status"] == nil {
                statusCode = 302
            }
        }

        var body = Data()
        if let json = spec["json"], JSONSerialization.isValidJSONObject(json) {
            body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
            headers["Content-Type"] = headers["Content-Type"] ?? "application/json; charset=utf-8"
        } else if let stringBody = spec["body"] as? String {
            body = Data(stringBody.utf8)
            headers["Content-Type"] = headers["Content-Type"] ?? "text/plain; charset=utf-8"
        }

        return HTTPResponse(
            statusCode: statusCode,
            headers: headers,
            body: body,
            delayMs: delayMs,
            closeConnection: closeConnection
        )
    }

    private func htmlResponse(status: Int, title: String, body: String) -> HTTPResponse {
        let page = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <title>\(htmlEscaped(title))</title>
          <style>
            body {
              font-family: -apple-system, BlinkMacSystemFont, sans-serif;
              padding: 32px 20px;
              background: #f7f7f8;
              color: #111;
            }
            h1 {
              font-size: 28px;
              margin: 0 0 16px 0;
            }
            form {
              display: flex;
              flex-direction: column;
              gap: 12px;
              max-width: 360px;
            }
            input {
              font-size: 16px;
              padding: 12px;
              border-radius: 10px;
              border: 1px solid #d0d5dd;
            }
            button {
              font-size: 16px;
              padding: 14px 18px;
              border: 0;
              border-radius: 12px;
              background: #0f62fe;
              color: white;
            }
          </style>
        </head>
        <body>
          \(body)
        </body>
        </html>
        """

        return HTTPResponse(
            statusCode: status,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            body: Data(page.utf8)
        )
    }

    private func jsonResponse(status: Int, payload: Any) -> HTTPResponse {
        let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
        return HTTPResponse(
            statusCode: status,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: body
        )
    }

    private func textResponse(status: Int, body: String) -> HTTPResponse {
        HTTPResponse(
            statusCode: status,
            headers: ["Content-Type": "text/plain; charset=utf-8"],
            body: Data(body.utf8)
        )
    }

    private func redirectResponse(location: String) -> HTTPResponse {
        HTTPResponse(
            statusCode: 302,
            headers: ["Location": location],
            body: Data()
        )
    }

    private func buildCallbackURL(redirectURI: String, code: String, state: String) -> String {
        guard var components = URLComponents(string: redirectURI) else {
            return redirectURI
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "code", value: code))
        if !state.isEmpty {
            queryItems.append(URLQueryItem(name: "state", value: state))
        }
        components.queryItems = queryItems
        return components.string ?? redirectURI
    }

    private func parseJSONDictionary(_ data: Data) -> [String: Any] {
        guard !data.isEmpty else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return [:]
        }
        return dictionary
    }

    private func parseURLEncodedForm(data: Data) -> [String: String] {
        guard let bodyString = String(data: data, encoding: .utf8), !bodyString.isEmpty else {
            return [:]
        }

        var values: [String: String] = [:]
        for pair in bodyString.components(separatedBy: "&") {
            guard !pair.isEmpty else { continue }
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = decodeFormComponent(String(parts[0]))
            let value = parts.count > 1 ? decodeFormComponent(String(parts[1])) : ""
            values[name] = value
        }
        return values
    }

    private func decodeFormComponent(_ raw: String) -> String {
        raw.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? raw
    }

    private func refreshTokenFromCookies(_ cookieHeader: String?) -> String? {
        guard let cookieHeader else { return nil }
        for segment in cookieHeader.components(separatedBy: ";") {
            let chunk = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard chunk.hasPrefix("fe_refresh_"), let separator = chunk.firstIndex(of: "=") else {
                continue
            }
            let valueIndex = chunk.index(after: separator)
            return String(chunk[valueIndex...])
        }
        return nil
    }

    private func emailFromAuthorizationHeader(_ header: String?) -> String? {
        guard let header, header.hasPrefix("Bearer ") else { return nil }
        let token = String(header.dropFirst("Bearer ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return emailFromBearerToken(token)
    }

    private func emailFromBearerToken(_ token: String) -> String? {
        let parts = token.components(separatedBy: ".")
        guard parts.count > 1, let payload = decodeBase64URLJSON(parts[1]) else { return nil }
        return payload["email"] as? String
    }

    private func decodeBase64URLJSON(_ value: String) -> [String: Any]? {
        guard !value.isEmpty else { return nil }
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padding = (4 - normalized.count % 4) % 4
        if padding > 0 {
            normalized += String(repeating: "=", count: padding)
        }

        guard let decoded = Data(base64Encoded: normalized),
              let object = try? JSONSerialization.jsonObject(with: decoded),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary
    }

    private func decodeSocialState(_ rawState: String) -> [String: Any]? {
        guard let data = rawState.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary
    }

    private func encodeBase64URLJSON(_ value: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: value)) ?? Data("{}".utf8)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func accessToken(email: String) -> String {
        let now = Int(Date().timeIntervalSince1970)
        let payload: [String: Any] = [
            "sub": "user-\(email.components(separatedBy: "@").first ?? "demo")",
            "email": email,
            "name": userName(from: email),
            "tenantId": tenantId(for: email),
            "tenantIds": [tenantId(for: email)],
            "profilePictureUrl": "https://example.com/avatar.png",
            "exp": now + 3600,
            "iat": now,
        ]

        let header = encodeBase64URLJSON(["alg": "none", "typ": "JWT"])
        let body = encodeBase64URLJSON(payload)
        return "\(header).\(body).signature"
    }

    private func authResponse(email: String, refreshToken: String) -> [String: Any] {
        let accessToken = accessToken(email: email)
        return [
            "token_type": "Bearer",
            "refresh_token": refreshToken,
            "access_token": accessToken,
            "id_token": accessToken,
        ]
    }

    private func tenantResponse(email: String) -> [String: Any] {
        let tenantId = tenantId(for: email)
        let now = "2026-03-26T00:00:00.000Z"
        return [
            "id": tenantId,
            "name": "\(userName(from: email)) Tenant",
            "tenantId": tenantId,
            "createdAt": now,
            "updatedAt": now,
            "isReseller": false,
            "metadata": "{}",
            "vendorId": "vendor-demo",
        ]
    }

    private func userResponse(email: String) -> [String: Any] {
        let tenant = tenantResponse(email: email)
        return [
            "id": "user-\(email.components(separatedBy: "@").first ?? "demo")",
            "email": email,
            "mfaEnrolled": false,
            "name": userName(from: email),
            "profilePictureUrl": "https://example.com/avatar.png",
            "phoneNumber": NSNull(),
            "profileImage": NSNull(),
            "roles": [],
            "permissions": [],
            "tenantId": tenant["id"] as Any,
            "tenantIds": [tenant["id"] as Any],
            "tenants": [tenant],
            "activeTenant": tenant,
            "activatedForTenant": true,
            "metadata": "{}",
            "verified": true,
            "superUser": false,
        ]
    }

    private func userName(from email: String) -> String {
        let localPart = email.components(separatedBy: "@").first ?? email
        let words = localPart
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
        return words.isEmpty ? "Demo User" : words.joined(separator: " ")
    }

    private func tenantId(for email: String) -> String {
        let localPart = email.components(separatedBy: "@").first ?? "demo"
        let normalized = localPart
            .replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: "_", with: "-")
        return "tenant-\(normalized)"
    }

    private func firstValue(_ query: [String: [String]], key: String, default defaultValue: String = "") -> String {
        query[key]?.first ?? defaultValue
    }

    private func normalizePath(_ path: String) -> String {
        if path.isEmpty { return "/" }
        if path.hasPrefix("/") { return path }
        return "/\(path)"
    }

    private func htmlEscaped(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func javaScriptLiteral(_ string: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [string])) ?? Data(#"[""]"#.utf8)
        let json = String(data: data, encoding: .utf8) ?? #"[""]"#
        return String(json.dropFirst().dropLast())
    }

    private func intValue(_ value: Any?, default defaultValue: Int = 0) -> Int {
        if let intValue = value as? Int { return intValue }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String, let intValue = Int(string) { return intValue }
        return defaultValue
    }

    private func boolValue(_ value: Any?) -> Bool {
        if let boolValue = value as? Bool { return boolValue }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String { return NSString(string: string).boolValue }
        return false
    }

    private func reasonPhrase(for statusCode: Int) -> String {
        switch statusCode {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 302: return "Found"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 408: return "Request Timeout"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        default: return HTTPURLResponse.localizedString(forStatusCode: statusCode).capitalized
        }
    }

    private func log(_ request: HTTPRequest) {
        let logged = LoggedRequest(method: request.method, path: request.path, target: request.target)
        requestLogLock.lock()
        requestLog.append(logged)
        requestLogLock.unlock()
        print("MockAuthServer \(logged.method) \(logged.target)")
    }

    private func hasRequest(method: String?, path: String) -> Bool {
        requestLogLock.lock()
        defer { requestLogLock.unlock() }
        return requestLog.contains {
            $0.path == path && (method == nil || $0.method == method)
        }
    }
}

private struct LoggedRequest {
    let method: String
    let path: String
    let target: String
}

private struct HTTPRequest {
    let method: String
    let target: String
    let path: String
    let query: [String: [String]]
    let headers: [String: String]
    let body: Data
}

private struct HTTPResponse {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
    let delayMs: Int
    let closeConnection: Bool

    init(
        statusCode: Int,
        headers: [String: String],
        body: Data,
        delayMs: Int = 0,
        closeConnection: Bool = false
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.delayMs = delayMs
        self.closeConnection = closeConnection
    }
}

private struct AuthCode {
    let email: String
    let redirectURI: String
    let state: String
}

private struct HostedLoginContext {
    let redirectURI: String
    let originalState: String
    let loginHint: String
}

private final class MockAuthState {
    private let queue = DispatchQueue(label: "com.frontegg.demo-embedded-e2e.mock-state")
    private var queuedResponses: [String: [[String: Any]]] = [:]
    private var authCodes: [String: AuthCode] = [:]
    private var hostedLoginContexts: [String: HostedLoginContext] = [:]
    private var completedHostedLogins: [String: String] = [:]
    private var refreshTokens: [String: String] = [:]

    init() {
        reset()
    }

    func reset() {
        queue.sync {
            queuedResponses = [:]
            authCodes = [:]
            hostedLoginContexts = [:]
            completedHostedLogins = [:]
            refreshTokens = [
                "signup-refresh-token": "signup@frontegg.com",
            ]
        }
    }

    func enqueue(method: String, path: String, responses: [[String: Any]]) {
        let key = queueKey(method: method, path: path)
        queue.sync {
            queuedResponses[key, default: []].append(contentsOf: responses)
        }
    }

    func dequeue(method: String, path: String) -> [String: Any]? {
        let key = queueKey(method: method, path: path)
        return queue.sync {
            guard var responses = queuedResponses[key], !responses.isEmpty else {
                return nil
            }
            let response = responses.removeFirst()
            if responses.isEmpty {
                queuedResponses.removeValue(forKey: key)
            } else {
                queuedResponses[key] = responses
            }
            return response
        }
    }

    func issueCode(email: String, redirectURI: String, state: String) -> String {
        queue.sync {
            let code = "code-\(UUID().uuidString.lowercased())"
            authCodes[code] = AuthCode(email: email, redirectURI: redirectURI, state: state)
            return code
        }
    }

    func issueHostedLoginContext(
        redirectURI: String,
        originalState: String,
        loginHint: String
    ) -> String {
        queue.sync {
            let hostedState = "hosted-\(UUID().uuidString.lowercased())"
            hostedLoginContexts[hostedState] = HostedLoginContext(
                redirectURI: redirectURI,
                originalState: originalState,
                loginHint: loginHint
            )
            return hostedState
        }
    }

    func hostedLoginContext(for hostedState: String) -> HostedLoginContext? {
        queue.sync {
            hostedLoginContexts[hostedState]
        }
    }

    func recordHostedPostloginCompletion(hostedState: String, email: String) {
        queue.sync {
            completedHostedLogins[hostedState] = email
        }
    }

    func completedHostedLoginEmail(for hostedState: String) -> String? {
        queue.sync {
            completedHostedLogins[hostedState]
        }
    }

    func consumeCode(_ code: String) -> AuthCode? {
        queue.sync {
            let authCode = authCodes[code]
            authCodes.removeValue(forKey: code)
            return authCode
        }
    }

    func authCode(for code: String) -> AuthCode? {
        queue.sync {
            authCodes[code]
        }
    }

    func saveRefreshToken(_ refreshToken: String, email: String) {
        queue.sync {
            refreshTokens[refreshToken] = email
        }
    }

    func email(forRefreshToken refreshToken: String) -> String? {
        queue.sync {
            refreshTokens[refreshToken]
        }
    }

    func invalidateRefreshToken(_ refreshToken: String) {
        _ = queue.sync {
            refreshTokens.removeValue(forKey: refreshToken)
        }
    }

    private func queueKey(method: String, path: String) -> String {
        "\(method.uppercased()) \(normalizedPath(path))"
    }

    private func normalizedPath(_ path: String) -> String {
        if path.isEmpty { return "/" }
        if path.hasPrefix("/") { return path }
        return "/\(path)"
    }
}
