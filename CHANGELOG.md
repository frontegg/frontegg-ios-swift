## v1.2.68
Fix: Improved token refresh reliability when enableSessionPerTenant is enabled
- Added migration-safe logic that falls back to legacy global tokens if tenant-specific tokens or lastActiveTenantId are not yet available (e.g. right after upgrading from a version without per-tenant sessions)
- This prevents one-time refresh failures on the first app launch after upgrade while still using existing tokens, and ensures a smoother transition to per-tenant token storage

Fix: Social login PKCE flow
 - Hardened the OAuth callback handler to be more defensive (better error checks, weak self, more logging).
  - Improved tenant-specific token refresh behavior, including safe fallback to legacy tokens for migration scenarios – making refresh failures less likely to log out existing users.
  - Added rich PKCE debug logging around token exchange so that future customer logs immediately reveal whether the verifier is present, its length, and the redirect URI used.
  - Ensured `WebAuthenticator` is always created with the correct presentation anchor and, for Microsoft, uses a non-ephemeral session while still using ephemeral sessions for other providers
### Sentry Error Tracking

- **Feature Flag**: Added `enableSentryLogging` in `Frontegg.plist` to enable/disable Sentry logging
- **Offline Support**: Configurable `sentryMaxQueueSize` (default: 30) for event queuing during offline periods
- **Comprehensive Breadcrumbs**: Automatic tracking of social login flows, OAuth callbacks, token refresh attempts, and associated domains configuration
- **Trace ID Correlation**: Trace IDs from API responses logged to Sentry breadcrumbs and local files

### Enhanced Logging

- **Social Login Visibility**: Detailed logging for `ASWebAuthenticationSession` flows including callback URLs, query parameters, and redirect success/failure
- **Associated Domains Verification**: Startup logging to verify associated domains configuration
- **Improved Error Messages**: Refresh token errors now include detailed API error messages

## Migration Notes

If you were using `enableTraceIdLogging`:

1. Remove `enableTraceIdLogging` from your `Frontegg.plist`
2. Add `enableSentryLogging`:
   
   <key>enableSentryLogging</key>
   <true/>
   ## Dependencies

- Added Sentry SDK dependency (`~> 8.46.0`)

## v1.2.67
- updated logout api 

## v1.2.66
- microsoft verification callback support

## v1.2.65
- updated to use `POST` instead of `GET`

## v1.2.64
- added web example `SignUp` flow with usage of `/frontegg/oauth/authorize/silent`

## v1.2.63
- Replaced silent authorize api  

## v1.2.62
- Offline Mode /test Calls Fixes
- Network Monitoring Enhancements
- Session Per Tenant Fixes
- Offline Authentication Improvements
- **New debug utility**: Added `TraceIdLogger` class to capture and store `frontegg-trace-id` headers from API responses
- **Configurable via plist**: Added `enableTraceIdLogging` boolean flag to `FronteggPlist` config
-  **Configurable monitoring interval**: Added `networkMonitoringInterval` config option (defaults to 10 seconds) to control frequency of `/test` calls
- fixed keychain error in demo app
- added more debug logs

## v1.2.61
- Only one subscription exists at a time (previous ones are canceled)
- Only one monitoring instance runs at a time (stopped before starting)
- Rapid successive calls are debounced to prevent multiple simultaneous starts
- /test calls only occur when the user is not logged in (no tokens)

## v1.2.60
- Before login (login screen shown): /test calls run every 10 seconds to check connectivity
- After login (user authenticated): /test calls stop completely, reducing network usage
- After logout: /test calls resume automatically
- Respects configuration: Only runs when enableOfflineMode == true in Frontegg.plist

## v1.2.59
- If the customer leaves enableOfflineMode false (the default), the SDK will no longer schedule the 10‑second background probes to `/fe-auth/test` at all, significantly reducing network usage during normal app usage (before and after authentication)
- `NetworkStatusMonitor.isActive` is still available and used for on-demand checks (e.g., before refreshing tokens) but those do not run every 10 seconds and won’t generate the continuous `/test` traffic they’re seeing
- Apps that do rely on Frontegg’s offline mode can keep `enableOfflineMode = true` and will retain the existing connectivity monitoring behavior

## v1.2.58
Fixed: Login with SSO OIDC.

## v1.2.57
Fixed: Google Login fails to redirect to app in embeddedMode when Safari session exists

## v1.2.56
https://frontegg.atlassian.net/browse/FR-22800

## v1.2.55
Redirect fixing for unlock account, forgot password and invite existing user to another tenant.

## v1.2.54
Fixed: post Activation Redirect to App fails, leaving user on "Opening Application" page

## v1.2.53
FR-22756 Unexpecred logouts fix.

## v1.2.52
Apple login fix in webview from embedded mode.
Magic links directLogin fix.

## v1.2.51
Added example of receiving token after login session below the "Sensitive action" button.

## v1.2.50
Fixed race condition for handleHostedLoginCallback method.
- Add a debounce when transitioning to offline to avoid brief misfires during quick reconnects
- Cancel any pending offline transition immediately when connectivity is restored

Implementation:
`FronteggAuth`:
1. Added offlineDebounceWork and offlineDebounceDelay = 0.6s
2. `disconnectedFromInternet()` now schedules setIsOfflineMode(true) after the debounce delay
3. `reconnectedToInternet()` cancels the pending work and sets isOfflineMode(false) immediately.

## v1.2.49
FR-22001 - Fix network connection monitor and add isOfflineMode indicator

<!-- CURSOR_SUMMARY -->
---

> [!NOTE]
> Introduce offline mode with a revamped network monitor, integrate reconnection-aware auth flows, and add demo UI for no-connection states.
> 
> - **Core Auth (`Sources/FronteggSwift/FronteggAuth.swift`)**:
>   - Add offline state handling: `reconnectedToInternet()`, `disconnectedFromInternet()`, `recheckConnection()`, and `setIsOfflineMode(false)` on successful auth.
>   - Integrate `NetworkStatusMonitor`: `configure(...)`, background monitoring, and gating feature-flag/social-config loads on `isActive`.
>   - Centralize retry/backoff via `handleOfflineLikeFailure(...)`; classify errors with `isConnectivityError(...)`; adjust token refresh/logout flows accordingly.
>   - Warm webview on main thread via `warmingWebViewAsync()` and clean up sequence.
> - **State (`Sources/FronteggSwift/state/FronteggState.swift`)**:
>   - Add `@Published isOfflineMode` with thread-safe setter.
> - **Networking (`Sources/FronteggSwift/utils/NetworkStatusMonitor.swift`)**:
>   - Overhaul to strict reachability: configurable base URL probes (HEAD/GET), cached state, path monitoring, periodic checks, and token-based onChange handlers; expose async `isActive`.
> - **Demo App**:
>   - Add `demo-embedded/NoConnectionPage.swift` and show it when `isOfflineMode` is true.
>   - Update `demo-embedded/MyApp.swift` to branch UI among loading, logged-in, login, and no-connection.
>   - Show "Offline Mode" indicator in `demo-embedded/UserPage.swift`.
> 
> <sup>Written by [Cursor Bugbot](https://cursor.com/dashboard?tab=bugbot) for commit 2ebd47da5bf85efa4ca14e6edef7bc31357cb3d9. This will update automatically on new commits. Configure [here](https://cursor.com/dashboard?tab=bugbot).</sup>
<!-- /CURSOR_SUMMARY -->

## v1.2.48
FR-22185 - Added support for trigger login with custom sso via WebAuthenticationSession
FR-22185 - Fix offline mode
FR-22001 - Support embedded social login flows
- Detect legacy social login flow when authorizationUrl starts with /identity/resources/auth/v2/user/sso/default/
- Add legacyAuthorizeURL method to generate legacy URLs
- Modify handleSocialLogin to automatically switch to legacy flow when needed
- Maintain backward compatibility with existing configurations

<!-- CURSOR_SUMMARY -->
---

> [!NOTE]
> Release v1.2.48 adding custom SSO via WebAuthenticationSession, legacy embedded social login handling, offline fix, and podspec/changelog updates.
> 
> - **Release v1.2.48**
>   - **Auth**: Add custom SSO login via `WebAuthenticationSession`.
>   - **Embedded Social Login**: Detect legacy flow, auto-switch when `authorizationUrl` matches legacy path, and add `legacyAuthorizeURL`.
>   - **Fix**: Offline mode.
> - **Versioning/Docs**: Update `CHANGELOG.md`, move `v1.2.47` to `CHANGELOG.old.md`, and bump `FronteggSwift.podspec` to `1.2.48`.
> 
> <sup>Written by [Cursor Bugbot](https://cursor.com/dashboard?tab=bugbot) for commit 31e66ee26717b8b0b7cd67052af8fad646e50ffe. This will update automatically on new commits. Configure [here](https://cursor.com/dashboard?tab=bugbot).</sup>
<!-- /CURSOR_SUMMARY -->

## v1.2.47
This PR introduces fixes and enhancements to the logout flow, adds offline mode support, and addresses critical issues in login handling.
- updated readme with new frontegg.plist keys

## v1.2.46
- Modified `generateRedirectUri` method. It includes `path` now.
- Modified `AuthorizeUrlGenerator.generate` method.  It includes `path` now.
- Check Internet connection before run DEBUG checks

## v1.2.45
- Reduce number of full page load when loading login page

## v1.2.44
- Fix ConfigurationCheck.swift
- Updated example projects UI
Fix e2e trigger ref
- Added background color to web view to avoid blinks on redirect 

## v1.2.43
- Fix publish workflow

## v1.2.42
### 🔧 Enhancements
- **Improved WKWebView Performance**  
  Optimized the WebView initialization and loading flow for faster render and smoother UX.

- **Unified Loading Indicators**  
  Standardized the loading experience across login pages and social login flows for consistent UI behavior.

- **Social Login Stability**  
  Prevented unnecessary reloads of the login page when canceling a social login popup.

- **Unified Loader Support**  
  Integrated support for a centralized loading mechanism across the SDK.

---

### 🐞 Bug Fixes
- Fixed various crash scenarios related to view lifecycle and state handling in authentication flows.

---

### 🧪 QA & Automation
- **Simulator E2E Tests Added**  
  Extended test coverage with end-to-end tests running on iOS simulators.

- **Pre-Release E2E Trigger**  
  Introduced automatic E2E test triggers before each release to catch issues

## v1.2.41
- clear `fe_refresh` cookie on logout 

## v1.2.40
- Updated README.md
- Clear `frontegg.com` while logout;
- Do not post identity/resources/auth/v1/logout if refreshToken is null
- Updated README.md

## v1.2.39
FR-20294 - Reset login completion when deep link triggered

## v1.2.38
- Updated docs.
- Fixed opening external urls
- Support deep linking for redirect in Embedded Login WebView

## v1.2.37
-Added `step-up` instruction.
- Fixed `step-up` callback

## v1.2.36
- Fixed step-up
- updated demo projects
- added application-id project

# v1.2.35
- Added automation of generation CHANGELOG.md
- made `DefaultLoader`.`customLoaderView` public for flutter capability
