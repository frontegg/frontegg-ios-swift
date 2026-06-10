import Foundation
import WebKit

@available(iOS 14.0, *)
final class AdminPortalBridge: NSObject, WKScriptMessageHandler {

    static let handlerName = "FronteggNativeBridge"
    static let callbackRegistry = "FronteggNativeBridgeCallbacks"

    static let capabilities: [String: Any] = [
        "getTokens": true,
        "requestAuthorize": true,
        "closeWindow": true,
        "useNativeLoader": true,
    ]

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

    private func handleGetTokens(callbackId: String?) {
        guard let callbackId = callbackId else {
            logger.error("AdminPortal: getTokens missing callbackId")
            return
        }
        Task { @MainActor in
            guard self.isTrustedOrigin() else {
                self.logger.error("AdminPortal: getTokens refused — untrusted origin \(self.webView?.url?.absoluteString ?? "?")")
                self.reject(callbackId: callbackId, message: "untrusted_origin")
                return
            }

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

    private func handleRequestAuthorize(payload: String?) {
        logger.info("AdminPortal: portal requested authorize (\(payload ?? "")) — dismissing to app")
        DispatchQueue.main.async { [weak self] in self?.onClose?() }
    }

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
