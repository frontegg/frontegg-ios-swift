//
//  LoginBoxFooter.swift
//
//  Hands a host-supplied footer to the embedded login box.
//

import Foundation

/// Builds the document-start script that hands a host-supplied footer to the
/// hosted login box, which renders it below the login screen's inputs.
///
/// The box reads `window.__fronteggLoginBoxFooter` and renders it through its own
/// `boxFooter` slot, the same slot the React SDK exposes. See `hostFooter.ts` in
/// oauth-service. The payload is structured (text and label/URL pairs), never markup,
/// and is sanitized here as well as in the box.
enum LoginBoxFooter {

    static let globalName = "__fronteggLoginBoxFooter"

    /// Schemes that can execute script or read local data; never admissible.
    private static let deniedSchemes: Set<String> = [
        "javascript", "data", "file", "blob", "about", "vbscript", "intent", "content"
    ]

    /// Returns `nil` when the footer is absent or has no usable rows, so callers
    /// can skip injecting a script entirely.
    static func script(_ footer: [String: Any]?) -> String? {
        guard let sanitized = sanitizedFooter(footer),
              let json = LoginBoxCustomization.encodeOverrides(sanitized) else {
            return nil
        }
        return "window.\(globalName) = \(json);"
    }

    /// Normalizes a host-supplied footer payload, dropping anything unsafe.
    ///
    /// Shape:
    /// ```
    /// [
    ///   "hideCaptchaBadge": true,
    ///   "rows": [
    ///     ["variant": "body",            // "body" | "fine"
    ///      "segments": [
    ///        ["text": "Don't have an account? "],
    ///        ["label": "Sign up now", "url": "myapp://sign-up"]
    ///      ]]
    ///   ]
    /// ]
    /// ```
    ///
    /// A segment whose URL fails the scheme check degrades to plain text rather
    /// than being dropped: the footer's usual job is a legal attribution, and a
    /// sentence missing a fragment reads as a bug, whereas an unlinked label
    /// still says what it needs to say.
    static func sanitizedFooter(_ footer: [String: Any]?) -> [String: Any]? {
        guard let footer,
              let rows = footer["rows"] as? [[String: Any]],
              !rows.isEmpty else {
            return nil
        }

        var sanitizedRows: [[String: Any]] = []

        for row in rows {
            guard let segments = row["segments"] as? [[String: Any]] else { continue }

            var sanitizedSegments: [[String: Any]] = []
            for segment in segments {
                if let text = segment["text"] as? String, !text.isEmpty {
                    sanitizedSegments.append(["text": text])
                    continue
                }
                guard let label = segment["label"] as? String, !label.isEmpty else { continue }

                if let url = segment["url"] as? String, let safe = sanitizedLinkUrl(url) {
                    sanitizedSegments.append(["label": label, "url": safe])
                } else {
                    sanitizedSegments.append(["text": label])
                }
            }

            guard !sanitizedSegments.isEmpty else { continue }

            let variant = (row["variant"] as? String) == "fine" ? "fine" : "body"
            sanitizedRows.append(["variant": variant, "segments": sanitizedSegments])
        }

        guard !sanitizedRows.isEmpty else { return nil }

        return [
            "hideCaptchaBadge": (footer["hideCaptchaBadge"] as? Bool) ?? false,
            "rows": sanitizedRows
        ]
    }

    /// Accepts an absolute `http(s)` URL, or a URL on one of the host app's own
    /// registered `CFBundleURLTypes` schemes.
    ///
    /// The value becomes an `href`, so anything else — `javascript:` above all —
    /// is dropped rather than injected. A host app is trusted, but this value
    /// can originate in remote configuration on its side, and the cost of the
    /// check is nothing.
    ///
    /// The app-scheme case is what makes a hand-off possible: a host that wants
    /// its sign-up flow presented in its own browser/session rather than inside
    /// this WebView points a footer link at its own scheme, and the navigation
    /// delegate's existing custom-scheme branch opens it and dismisses the box.
    static func sanitizedLinkUrl(_ url: String?) -> String? {
        guard let url, !url.isEmpty,
              let components = URLComponents(string: url),
              let scheme = components.scheme?.lowercased() else {
            return nil
        }

        if scheme == "http" || scheme == "https" {
            guard let host = components.host, !host.isEmpty else { return nil }
            return url
        }

        // Denied ahead of the app-scheme check so the guard that actually
        // matters cannot be reached through a bundle that registers, say,
        // `data` as one of its own schemes.
        if deniedSchemes.contains(scheme) { return nil }

        guard appUrlSchemes().contains(scheme) else { return nil }

        return carriesOAuthCallbackParameter(url) ? nil : url
    }

    /// Whether the custom-scheme branch would treat this URL as an OAuth callback rather than a hand-off.
    static func carriesOAuthCallbackParameter(_ url: String) -> Bool {
        let standardQueryNames: [String] = URLComponents(string: url)?.queryItems?.map { $0.name } ?? []
        let delegateQueryNames: [String] = getQueryItems(url).map { Array($0.keys) } ?? []
        let queryNames: [String] = standardQueryNames + delegateQueryNames
        return queryNames.contains { (queryName: String) -> Bool in oauthCallbackParameterNames.contains(queryName) }
    }

    /// The configured link URLs that fail `sanitizedLinkUrl` and so render as plain text,
    /// cut before any query or fragment, since those can carry an invite code.
    static func rejectedLinkUrls(_ footer: [String: Any]?) -> [String] {
        guard let rows = footer?["rows"] as? [[String: Any]] else { return [] }

        var rejectedUrls: [String] = []
        for row in rows {
            guard let segments = row["segments"] as? [[String: Any]] else { continue }
            for segment in segments {
                let text: String = (segment["text"] as? String) ?? ""
                let label: String = (segment["label"] as? String) ?? ""
                guard text.isEmpty, !label.isEmpty, let configuredUrl = segment["url"] else { continue }
                guard sanitizedLinkUrl(configuredUrl as? String) == nil else { continue }

                let describedUrl: String = String(describing: configuredUrl)
                let redactedUrl: Substring = describedUrl.prefix(while: { (character: Character) -> Bool in
                    character != "?" && character != "#"
                })
                rejectedUrls.append(String(redactedUrl))
            }
        }
        return rejectedUrls
    }

    private static let oauthCallbackParameterNames: Set<String> = ["code", "error", "error_description"]

    /// The `http(s)` footer URLs, which must be opened outside the login box.
    ///
    /// The box's WebView has no navigation chrome, so letting an attribution
    /// link load in place strands the user with no way back. The navigation
    /// delegate consults this exact-match set and hands those URLs to the OS
    /// instead — an allowlist rather than a general "off-origin" rule, because
    /// the box legitimately navigates to social identity providers.
    static func footerExternalUrls(_ footer: [String: Any]?) -> Set<String> {
        guard let sanitized = sanitizedFooter(footer),
              let rows = sanitized["rows"] as? [[String: Any]] else {
            return []
        }

        var urls: Set<String> = []
        for row in rows {
            guard let segments = row["segments"] as? [[String: Any]] else { continue }
            for segment in segments {
                guard let url = segment["url"] as? String,
                      let scheme = URLComponents(string: url)?.scheme?.lowercased() else { continue }
                if scheme == "http" || scheme == "https", let linkKey = canonicalLinkKey(url) {
                    urls.insert(linkKey)
                }
            }
        }
        return urls
    }

    /// Whether a navigation is to one of the footer's `http(s)` links.
    static func isExternalFooterLink(_ url: URL, footer: [String: Any]?) -> Bool {
        guard let linkKey = canonicalLinkKey(url.absoluteString) else { return false }
        return footerExternalUrls(footer).contains(linkKey)
    }

    /// Normalizes a URL the way WebKit does before navigating, so a configured link
    /// still matches: dot segments resolved, lowercased scheme and host, `/` for an empty path, no default port.
    static func canonicalLinkKey(_ url: String) -> String? {
        guard let standardizedUrl = URL(string: url)?.standardized,
              var components = URLComponents(url: standardizedUrl, resolvingAgainstBaseURL: false) else { return nil }
        let scheme = components.scheme?.lowercased()
        components.scheme = scheme
        components.host = components.host?.lowercased()
        if components.path.isEmpty {
            components.path = "/"
        }
        if (scheme == "https" && components.port == 443) || (scheme == "http" && components.port == 80) {
            components.port = nil
        }
        return components.string
    }

    /// The host app's registered URL schemes, lowercased.
    static func appUrlSchemes() -> [String] {
        guard let urlTypes = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] else {
            return []
        }
        return urlTypes
            .compactMap { $0["CFBundleURLSchemes"] as? [String] }
            .flatMap { $0 }
            .map { $0.lowercased() }
    }
}
