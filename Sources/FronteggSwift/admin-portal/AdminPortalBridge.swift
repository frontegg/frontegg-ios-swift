//
//  AdminPortalBridge.swift
//  FronteggSwift
//
//  JS <-> native bridge for the embedded admin portal WebView.
//
//  The hosted admin portal (admin-box, served from /oauth/portal) detects the
//  mobile SDK via `window.FronteggNativeBridgeFunctions` and, instead of running
//  its own cookie-based silent-authorize, asks the native SDK for the current
//  OAuth tokens. Native stays the single source of truth for the session; the
//  portal builds its login state from the access/refresh token we hand back.
//  This is why the portal no longer bounces to /oauth/account/login — it never
//  depends on the WebView cookie jar (which is empty in hosted mode and a stale
//  single-use value in embedded mode).
//
//  Contract (shared with admin-box `FronteggNativeModule` and the Android
//  `FronteggNativeBridge`):
//
//    JS -> native : window.webkit.messageHandlers.FronteggNativeBridge
//                     .postMessage(JSON.stringify({ action, callbackId, payload }))
//    native -> JS : window.FronteggNativeBridgeCallbacks["<callbackId>"]
//                     .resolve(<json>)  |  .reject("<message>")
//
//  Actions:
//    getTokens(callbackId)      -> resolve { accessToken, refreshToken }
//    requestAuthorize(payload)  -> native handles (re)authorization
//    closeWindow(payload)       -> dismiss the portal
//
//  Security: getTokens hands the keychain-backed refresh token to web JS, so it
//  is ONLY honored when the WebView's current origin matches the configured
//  Frontegg baseUrl. Any other origin is refused — this keeps a compromised or
//  redirected page from exfiltrating the long-lived refresh token.
//

import Foundation
import WebKit

@available(iOS 14.0, *)
final class AdminPortalBridge: NSObject, WKScriptMessageHandler {

    /// WKScriptMessageHandler name. Must match the JS side
    /// (`window.webkit.messageHandlers.FronteggNativeBridge`) and the existing
    /// login-box bridge so `FronteggNativeModule.isIOSNativeBridgeAvailable()`
    /// resolves true inside the portal WebView.
    static let handlerName = "FronteggNativeBridge"

    /// JS-side promise registry the native layer resolves into. Defined by
    /// admin-box's `FronteggNativeModule`; named here so both sides agree.
    static let callbackRegistry = "FronteggNativeBridgeCallbacks"

    /// Capabilities advertised to the portal via
    /// `window.FronteggNativeBridgeFunctions` so the web's `isAvailable(method)`
    /// checks pass.
    static let capabilities: [String: Any] = [
        "getTokens": true,
        "requestAuthorize": true,
        "closeWindow": true,
        "useNativeLoader": true,
    ]

    /// JSON literal for the capability map, injected at document start.
    static var capabilitiesJSON: String {
        guard let data = try? JSONSerialization.data(withJSONObject: capabilities),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    weak var webView: WKWebView?
    private let fronteggAuth: FronteggAuth
    private let onClose: (() -> Void)?
    private let logger = getLogger("AdminPortalBridge")

    init(fronteggAuth: FronteggAuth = .shared, onClose: (() -> Void)?) {
        self.fronteggAuth = fronteggAuth
        self.onClose = onClose
    }

    private struct BridgeMessage: Decodable {
        let action: String
        let callbackId: String?
        let payload: String?
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == AdminPortalBridge.handlerName,
              let jsonString = message.body as? String,
              let data = jsonString.data(using: .utf8),
              let msg = try? JSONDecoder().decode(BridgeMessage.self, from: data) else {
            return
        }

        switch msg.action {
        case "getTokens":
            handleGetTokens(callbackId: msg.callbackId)
        case "requestAuthorize":
            handleRequestAuthorize(payload: msg.payload)
        case "closeWindow":
            logger.info("AdminPortal: portal requested closeWindow (\(msg.payload ?? ""))")
            DispatchQueue.main.async { [weak self] in self?.onClose?() }
        default:
            logger.trace("AdminPortal: unknown bridge action \(msg.action)")
        }
    }

    // MARK: - getTokens

    private func handleGetTokens(callbackId: String?) {
        guard let callbackId = callbackId else {
            logger.error("AdminPortal: getTokens missing callbackId")
            return
        }
        Task { @MainActor in
            // Security gate: only hand tokens to the trusted Frontegg origin.
            guard self.isTrustedOrigin() else {
                self.logger.error("AdminPortal: getTokens refused — untrusted origin \(self.webView?.url?.absoluteString ?? "?")")
                self.reject(callbackId: callbackId, message: "untrusted_origin")
                return
            }

            // The SDK owns refresh; make sure the access token we hand back is
            // valid before the portal uses it to load /me + /tenants.
            _ = await self.fronteggAuth.refreshTokenIfNeeded()

            guard let accessToken = self.fronteggAuth.accessToken,
                  let refreshToken = self.fronteggAuth.refreshToken,
                  !accessToken.isEmpty, !refreshToken.isEmpty else {
                self.reject(callbackId: callbackId, message: "no_tokens")
                return
            }

            self.resolve(callbackId: callbackId, jsonObject: [
                "accessToken": accessToken,
                "refreshToken": refreshToken,
            ])
        }
    }

    // MARK: - requestAuthorize

    private func handleRequestAuthorize(payload: String?) {
        // The portal's silent path failed or it explicitly asked for a fresh
        // login (prompt=login). Native owns authorization: dismiss back to the
        // app so the SDK's normal login flow can re-authenticate the user.
        // (In the common case the user is already authenticated when the SDK
        // opens the portal, so getTokens succeeds and this never fires.)
        logger.info("AdminPortal: portal requested authorize (\(payload ?? "")) — dismissing to app")
        DispatchQueue.main.async { [weak self] in self?.onClose?() }
    }

    // MARK: - helpers

    @MainActor
    private func isTrustedOrigin() -> Bool {
        guard let current = webView?.url,
              let base = URL(string: fronteggAuth.baseUrl) else { return false }
        return current.scheme == base.scheme
            && current.host == base.host
            && current.port == base.port
    }

    private func resolve(callbackId: String, jsonObject: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: jsonObject),
              let json = String(data: data, encoding: .utf8) else {
            reject(callbackId: callbackId, message: "serialize_failed")
            return
        }
        let registry = AdminPortalBridge.callbackRegistry
        let js = """
        (function(){var r=window.\(registry); if(r && r["\(callbackId)"]){ r["\(callbackId)"].resolve(\(json)); delete r["\(callbackId)"]; }})();
        """
        evaluate(js)
    }

    private func reject(callbackId: String, message: String) {
        let safe = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let registry = AdminPortalBridge.callbackRegistry
        let js = """
        (function(){var r=window.\(registry); if(r && r["\(callbackId)"]){ r["\(callbackId)"].reject("\(safe)"); delete r["\(callbackId)"]; }})();
        """
        evaluate(js)
    }

    private func evaluate(_ js: String) {
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
