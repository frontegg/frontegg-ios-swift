//
//  LoginBoxFooter.swift
//

import Foundation

/// Builds the document-start script that assigns `window.__fronteggLoginBoxFooter`,
/// which the hosted login box renders in its `boxFooter` slot.
enum LoginBoxFooter {

    static let globalName = "__fronteggLoginBoxFooter"

    private static let deniedSchemes: Set<String> = [
        "javascript", "data", "file", "blob", "about", "vbscript", "intent", "content"
    ]

    private static let oauthCallbackParameterNames: Set<String> = ["code", "error", "error_description"]

    /// Returns `nil` when the footer is absent or has no usable rows.
    static func script(_ footer: [String: Any]?) -> String? {
        guard let sanitized = sanitizedFooter(footer),
              let json = LoginBoxCustomization.encodeOverrides(sanitized) else {
            return nil
        }
        return "window.\(globalName) = \(json);"
    }

    /// Keeps text and label/URL segments only; a link whose URL fails `sanitizedLinkUrl` becomes text.
    static func sanitizedFooter(_ footer: [String: Any]?, appSchemes: [String] = appUrlSchemes()) -> [String: Any]? {
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

                if let url = segment["url"] as? String, let safe = sanitizedLinkUrl(url, appSchemes: appSchemes) {
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

    /// Accepts an absolute `http(s)` URL, or a URL on one of `appSchemes` that the
    /// custom-scheme branch would not treat as an OAuth callback.
    static func sanitizedLinkUrl(_ url: String?, appSchemes: [String] = appUrlSchemes()) -> String? {
        guard let url, !url.isEmpty,
              let components = URLComponents(string: url),
              let scheme = components.scheme?.lowercased() else {
            return nil
        }

        if scheme == "http" || scheme == "https" {
            guard let host = components.host, !host.isEmpty else { return nil }
            return url
        }

        if deniedSchemes.contains(scheme) { return nil }

        guard CustomWebView.isAppUrlScheme(scheme, appSchemes: appSchemes) else { return nil }

        return carriesOAuthCallbackParameter(url) ? nil : url
    }

    /// Checks both the standard query and the delegate's parse, which reads a `#` fragment as query.
    static func carriesOAuthCallbackParameter(_ url: String) -> Bool {
        let standardQueryNames: [String] = URLComponents(string: url)?.queryItems?.map { $0.name } ?? []
        let delegateQueryNames: [String] = getQueryItems(url).map { Array($0.keys) } ?? []
        let queryNames: [String] = standardQueryNames + delegateQueryNames
        return queryNames.contains { (queryName: String) -> Bool in oauthCallbackParameterNames.contains(queryName) }
    }

    /// The configured link URLs that render as plain text, cut before any query or fragment.
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

    /// The footer's `http(s)` links in `canonicalLinkKey` form; the navigation delegate opens these outside the box.
    static func footerExternalUrls(_ footer: [String: Any]?, appSchemes: [String] = appUrlSchemes()) -> Set<String> {
        guard let sanitized = sanitizedFooter(footer, appSchemes: appSchemes),
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

    static func isExternalFooterLink(_ url: URL, externalUrls: Set<String>) -> Bool {
        guard !externalUrls.isEmpty, let linkKey = canonicalLinkKey(url.absoluteString) else { return false }
        return externalUrls.contains(linkKey)
    }

    /// Normalizes a URL the way WebKit does before navigating: dot segments resolved,
    /// lowercased scheme and host, `/` for an empty path, no default port.
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

    /// The host app's registered `CFBundleURLTypes` schemes, lowercased.
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
