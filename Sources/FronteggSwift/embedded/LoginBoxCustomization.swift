//
//  LoginBoxCustomization.swift
//
//  Lets a host app theme and re-word the embedded login box at runtime.
//

import Foundation

/// Builds the document-start script that applies app-supplied `themeV2` and
/// `localizations` overrides to the embedded login box.
///
/// The hosted login box resolves its own appearance by `fetch`ing
/// `/frontegg/metadata?entityName=adminBox` and reading `rows[0].configuration`.
/// Rather than styling the rendered DOM — whose class names are generated and
/// change between login-box releases — this script wraps `window.fetch`,
/// waits for that specific response, and deep-merges the app's values into the
/// configuration before the box parses it. Every other request passes through
/// untouched, and any failure falls back to the original response.
///
/// This keeps customization on Frontegg's own documented configuration shape,
/// so it survives login-box upgrades.
enum LoginBoxCustomization {

    /// Returns `nil` when there is nothing to override, so callers can skip
    /// injecting a script entirely.
    static func script(themeOptions: [String: Any]?, localizations: [String: Any]?) -> String? {
        var overrides: [String: Any] = [:]

        if let themeOptions, !themeOptions.isEmpty {
            overrides["themeV2"] = themeOptions
        }
        if let localizations, !localizations.isEmpty {
            overrides["localizations"] = localizations
        }

        guard !overrides.isEmpty, let json = encodeOverrides(overrides) else {
            return nil
        }
        return template.replacingOccurrences(of: "__FRONTEGG_OVERRIDES__", with: json)
    }

    /// JSON-encodes the overrides for embedding in a JavaScript source string.
    static func encodeOverrides(_ overrides: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(overrides),
              let data = try? JSONSerialization.data(withJSONObject: overrides, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }

        // U+2028 and U+2029 are valid inside JSON but terminate a line in
        // JavaScript source, which would break the script we embed them in.
        return json
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    /// Substring identifying the login box's own metadata request.
    static let metadataPath = "/frontegg/metadata?entityName=adminBox"

    private static let template = """
    (function () {
      if (window.__fronteggLoginBoxOverridesInstalled) { return; }
      var originalFetch = window.fetch;
      if (typeof originalFetch !== 'function') { return; }
      window.__fronteggLoginBoxOverridesInstalled = true;

      var overrides = __FRONTEGG_OVERRIDES__;
      var METADATA_PATH = '/frontegg/metadata?entityName=adminBox';

      function isPlainObject(value) {
        return value !== null && typeof value === 'object' && !Array.isArray(value);
      }

      // Host values win on conflict; nested objects merge rather than replace so
      // untouched keys keep whatever the environment already configured.
      function deepMerge(target, source) {
        Object.keys(source).forEach(function (key) {
          var incoming = source[key];
          if (isPlainObject(incoming) && isPlainObject(target[key])) {
            deepMerge(target[key], incoming);
          } else {
            target[key] = incoming;
          }
        });
        return target;
      }

      function requestUrl(input) {
        if (typeof input === 'string') { return input; }
        if (input && typeof input.url === 'string') { return input.url; }
        if (input && typeof input.href === 'string') { return input.href; }
        return '';
      }

      window.fetch = function (input, init) {
        var pending = originalFetch.apply(this, arguments);
        if (requestUrl(input).indexOf(METADATA_PATH) === -1) { return pending; }

        return pending.then(function (response) {
          if (!response || !response.ok) { return response; }

          return response.clone().json().then(function (body) {
            var configuration =
              body && body.rows && body.rows[0] && body.rows[0].configuration;
            if (!isPlainObject(configuration)) { return response; }

            deepMerge(configuration, overrides);

            return new Response(JSON.stringify(body), {
              status: response.status,
              statusText: response.statusText,
              headers: { 'Content-Type': 'application/json' }
            });
          }).catch(function () {
            // Malformed or already-consumed body: leave the box on the
            // environment's own configuration rather than failing the request.
            return response;
          });
        });
      };
    })();
    """
}
