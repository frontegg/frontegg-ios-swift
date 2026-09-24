//
//  LoginBoxFooter.swift
//
//  Lets a host app append content below the embedded login box's card.
//

import Foundation

/// Builds the document-start script that renders a host-supplied footer below the
/// embedded login box's card, on its login screen only.
///
/// The box's configuration has no slot for content below the card — the React SDK
/// exposes a `boxFooter` render prop for exactly this, but that has no equivalent
/// when the box is served into a WebView. Host apps that must show something there
/// (a sign-up entry point, or the reCAPTCHA attribution Google's terms require when
/// the badge is hidden) have nowhere else to put it.
///
/// Unlike ``LoginBoxCustomization``, which hands values to the box's own
/// configuration, the footer is built in the DOM — but from a *structured* payload
/// (text and label/URL pairs) rather than host-supplied HTML, and anchored on
/// `[data-test-id="root-element"]`. A test id is part of the box's test contract
/// rather than its generated styling, which is what makes this narrow exception
/// tolerable where CSS/class-name styling would not be. No host string is ever
/// interpreted as markup.
enum LoginBoxFooter {

    /// Schemes that can execute script or read local data; never admissible.
    private static let deniedSchemes: Set<String> = [
        "javascript", "data", "file", "blob", "about", "vbscript", "intent", "content"
    ]

    /// Returns `nil` when the footer is absent or has no usable rows, so callers
    /// can skip injecting a script entirely.
    static func script(_ footer: [String: Any]?) -> String? {
        guard let sanitized = sanitizedFooter(footer),
              let json = encodeJson(sanitized) else {
            return nil
        }
        return template.replacingOccurrences(of: "__FRONTEGG_FOOTER__", with: json)
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

        return appUrlSchemes().contains(scheme) ? url : nil
    }

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
                if scheme == "http" || scheme == "https" {
                    urls.insert(url)
                }
            }
        }
        return urls
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

    /// JSON-encodes the footer for embedding in a JavaScript source string.
    static func encodeJson(_ value: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }

        return json
            // JSONSerialization writes `/` as `\/`. Harmless — JSON and
            // JavaScript both read `\/` as `/` — but it makes every link in a
            // script dump hard to read and hard to assert on.
            .replacingOccurrences(of: "\\/", with: "/")
            // U+2028 and U+2029 are valid inside JSON but terminate a line in
            // JavaScript source, which would break the script we embed them in.
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    private static let template = """
    (function () {
      if (window.__fronteggLoginBoxFooterInstalled) { return; }
      window.__fronteggLoginBoxFooterInstalled = true;

      var FOOTER = __FRONTEGG_FOOTER__;
      var FOOTER_ID = 'frontegg-login-box-footer';
      var ROOT_SELECTOR = '[data-test-id="root-element"]';
      // The footer follows the login screen only, mirroring the React SDK where
      // `boxFooter` is configured under `login` and the other screens
      // (forgot-password, MFA, signup) carry their own. Keyed on the login
      // title's test id, which is present on that screen and no other.
      var LOGIN_MARKER = '[data-test-id="login-page-title"]';

      // ---- footer ----------------------------------------------------------
      // Google's badge is rendered into the light DOM at body level, so a
      // document-level stylesheet reaches it even though the box itself lives
      // in a shadow root. Hiding it is only permitted alongside the visible
      // attribution the host supplies in `rows`.
      function hideCaptchaBadge() {
        if (!FOOTER.hideCaptchaBadge) { return; }
        if (document.getElementById(FOOTER_ID + '-badge-style')) { return; }
        var head = document.head || document.documentElement;
        if (!head) { return; }
        var style = document.createElement('style');
        style.id = FOOTER_ID + '-badge-style';
        style.textContent = '.grecaptcha-badge{visibility:hidden!important;}';
        head.appendChild(style);
      }

      function boxShadowRoot() {
        var found = null;
        var all = document.querySelectorAll('*');
        for (var i = 0; i < all.length; i++) {
          var host = all[i];
          if (host.shadowRoot && host.shadowRoot.querySelector(ROOT_SELECTOR)) {
            found = host.shadowRoot;
            break;
          }
        }
        return found;
      }

      // The box nests several full-height centring wrappers inside
      // [root-element] before the card. Descend while a wrapper has exactly one
      // child that still fills it; the first child that does NOT fill its
      // parent is the card, so we stop on the card's parent and append there.
      // The footer then flows directly under the card, and that column's
      // justify-content:center re-centres the pair.
      //
      // Deliberately geometric rather than structural: it reads the layout the
      // box actually produced instead of hard-coding a depth, so an added or
      // removed wrapper does not silently move the footer inside the card.
      function insertionPoint(shadowRoot) {
        var node = shadowRoot.querySelector(ROOT_SELECTOR);
        if (!node) { return null; }
        var guard = 0;
        while (node.childElementCount === 1 && guard++ < 10) {
          var child = node.firstElementChild;
          var parentHeight = node.getBoundingClientRect().height;
          var childHeight = child.getBoundingClientRect().height;
          if (!(parentHeight > 0 && childHeight >= 0.9 * parentHeight)) { break; }
          node = child;
        }
        return node;
      }

      function buildRow(row) {
        var line = document.createElement('div');
        var fine = row.variant === 'fine';
        line.style.cssText = [
          'text-align:center',
          'margin-top:' + (fine ? '24px' : '16px'),
          'font-size:' + (fine ? '9px' : '14px'),
          'line-height:1.3',
          'color:' + (fine ? 'rgba(0,0,0,0.6)' : 'rgba(0,0,0,0.87)'),
          'font-family:inherit'
        ].join(';');

        (row.segments || []).forEach(function (segment) {
          if (segment.url) {
            var anchor = document.createElement('a');
            // textContent, never innerHTML: host copy is never markup.
            anchor.textContent = segment.label;
            anchor.setAttribute('href', segment.url);
            anchor.style.cssText =
              'font-size:inherit;line-height:inherit;color:#2e74c7;text-decoration:none';
            line.appendChild(anchor);
          } else if (segment.text) {
            line.appendChild(document.createTextNode(segment.text));
          }
        });

        return line;
      }

      function renderFooter() {
        var shadowRoot = boxShadowRoot();
        if (!shadowRoot) { return; }

        var existing = shadowRoot.querySelector('#' + FOOTER_ID);
        var onLoginScreen = !!shadowRoot.querySelector(LOGIN_MARKER);

        if (!onLoginScreen) {
          if (existing) { existing.remove(); }
          return;
        }
        // Still mounted where we put it: nothing to do. React re-rendering the
        // card can detach it, which is what the observer below is for.
        if (existing && existing.isConnected) { return; }

        var target = insertionPoint(shadowRoot);
        if (!target) { return; }

        var wrapper = document.createElement('div');
        wrapper.id = FOOTER_ID;
        wrapper.style.cssText = 'width:100%;display:block;flex:0 0 auto';
        (FOOTER.rows || []).forEach(function (row) {
          wrapper.appendChild(buildRow(row));
        });
        target.appendChild(wrapper);

        hideCaptchaBadge();
      }

      // This script runs at document start, so the box does not exist yet, and
      // its screen changes happen inside a shadow root — which a
      // MutationObserver on `document` does not see. So: poll until the shadow
      // root appears, then observe it directly, keeping a slow poll as a
      // backstop in case the box is re-created wholesale.
      var observed = null;
      function attach() {
        renderFooter();
        var shadowRoot = boxShadowRoot();
        if (!shadowRoot || observed === shadowRoot) { return; }
        if (typeof MutationObserver !== 'function') { return; }
        observed = shadowRoot;
        new MutationObserver(function () {
          renderFooter();
        }).observe(shadowRoot, { childList: true, subtree: true });
      }

      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', attach);
      } else {
        attach();
      }
      setInterval(attach, 500);
    })();
    """
}
