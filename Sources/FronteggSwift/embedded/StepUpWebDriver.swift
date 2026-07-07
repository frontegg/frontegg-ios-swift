//
//  StepUpWebDriver.swift
//
//  FR-24939 — native-side step-up routing for the embedded login WebView.
//

import Foundation
import WebKit

/// FR-24939: The deployed hosted-login box bootstraps via its non-step-up authorize
/// path, which contains no native step-up handling. As a result an embedded step-up
/// authorize URL (`acr_values` + `max_age`) is silently token-refreshed and the box
/// renders a blank page instead of routing to its step-up (MFA) page.
///
/// Until the box itself detects native step-up on that path, we drive it from the
/// native side. While presenting a step-up flow we inject a `documentStart` script
/// that:
///   1. seeds the box's step-up `localStorage` contract (`SHOULD_STEP_UP`,
///      `FRONTEGG_OAUTH_STEP_UP_MAX_AGE`),
///   2. rewrites the URL (before the box reads it) to the box's step-up route so it
///      renders the MFA challenge, and
///   3. points the box's after-auth redirect (`FRONTEGG_AFTER_AUTH_REDIRECT_URL`)
///      back at the original authorize URL.
///
/// When step-up completes, the box performs a full navigation to that authorize URL —
/// now with an elevated session — which yields an elevated `code` that the existing
/// OAuth callback interception in `CustomWebView` exchanges into a stepped-up token.
/// No new native token-capture path is required.
enum StepUpWebDriver {

    /// Name of the `WKScriptMessageHandler` the driver posts diagnostics to.
    static let messageHandlerName = "FronteggStepUpDriver"

    /// Builds the `documentStart` script for the given original step-up authorize URL.
    static func script(authorizeUrl: URL) -> String {
        let afterAuth = jsStringLiteral(authorizeUrl.absoluteString)
        return """
        (function () {
          function report(m) {
            try { window.webkit.messageHandlers.\(messageHandlerName).postMessage(String(m)); } catch (e) {}
          }
          try {
            var loc = window.location;
            // Already on the step-up route (e.g. the box's own redirect) — nothing to do.
            if (loc.pathname.indexOf('/account/step-up') !== -1) { return; }
            var params = new URLSearchParams(loc.search);
            // Only act on the step-up authorize/prelogin document.
            if (!params.get('acr_values')) { report('skip: no acr_values on ' + loc.pathname); return; }

            var rawMaxAge = params.get('max_age');
            var maxAge = null;
            if (rawMaxAge != null) {
              var parsed = parseInt(parseFloat(rawMaxAge), 10);
              if (!isNaN(parsed)) { maxAge = String(parsed); }
            }

            var ls = window.localStorage;
            ls.setItem('SHOULD_STEP_UP', 'true');
            if (maxAge) { ls.setItem('FRONTEGG_OAUTH_STEP_UP_MAX_AGE', maxAge); }
            // Absolute http(s) URL => the box treats the post-MFA redirect as a full
            // navigation, re-hitting /oauth/authorize with the now-elevated session so a
            // stepped-up code is issued and captured by the native OAuth callback.
            ls.setItem('FRONTEGG_AFTER_AUTH_REDIRECT_URL', \(afterAuth));

            // Hosted-login basename = current path minus its last segment
            // (e.g. '/oauth' from '/oauth/prelogin'); step-up route is
            // '<basename>/account/step-up'. Preserve the existing query params and add
            // the 'maxAge' param the step-up page reads (note: distinct from OAuth 'max_age').
            var path = loc.pathname;
            var basename = path.substring(0, path.lastIndexOf('/'));
            var search = loc.search || '';
            if (maxAge) { search += (search ? '&' : '?') + 'maxAge=' + maxAge; }
            var target = basename + '/account/step-up' + search;

            window.history.replaceState(null, '', loc.origin + target);
            report('routed to ' + basename + '/account/step-up (maxAge=' + maxAge + ')');

            // Diagnostics (self-terminating): trace what the box does after the redirect so
            // the native log alone shows whether StepUpPage renders / the session generate
            // fires, without needing Safari Web Inspector. TODO: drop before final PR.
            try {
              var origFetch = window.fetch;
              window.fetch = function (input, init) {
                try {
                  var u = (typeof input === 'string') ? input : (input && input.url) || '';
                  if (u.indexOf('step-up') !== -1) { report('fetch ' + ((init && init.method) || 'GET') + ' ' + u); }
                } catch (e) {}
                return origFetch.apply(this, arguments);
              };
            } catch (e) {}
            var ticks = 0;
            var iv = setInterval(function () {
              ticks++;
              report('t+' + ticks + 's path=' + window.location.pathname);
              if (ticks >= 8) { clearInterval(iv); }
            }, 1000);
          } catch (e) {
            report('error: ' + (e && e.message ? e.message : e));
          }
        })();
        """
    }

    /// Encodes a string as a JS string literal (quoted + escaped) via JSON.
    private static func jsStringLiteral(_ value: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [value]),
           let json = String(data: data, encoding: .utf8) {
            // json is `["...."]`; strip the surrounding array brackets to get the literal.
            return String(json.dropFirst().dropLast())
        }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

/// Surfaces step-up driver diagnostics from the WebView into the native log — the box
/// JS console is otherwise invisible on iOS, so this makes the routing observable.
final class StepUpWebDriverDiagnostics: NSObject, WKScriptMessageHandler {
    private let logger = getLogger("StepUpWebDriver")

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        logger.info("[step-up driver] \(String(describing: message.body))")
    }
}
