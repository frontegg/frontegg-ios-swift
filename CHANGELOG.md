## v1.3.0
<!-- CURSOR_SUMMARY -->
> [!NOTE]
> **Medium Risk**
> Touches core auth/token hydration and tenant resolution flows; incorrect handling could lead to token/keychain desync or users being assigned the wrong active tenant. Changes are scoped but affect login/refresh paths and token rotation behavior.
> 
> **Overview**
> Prevents unexpected logouts caused by tenant retrieval failures during auth by making `Api.me` return a `MeResult` that can include **re-refreshed tokens** when `/me/tenants` fails after retry (e.g., webhook/prehook race changing tenant during JWT issuance).
> 
> Updates credential hydration in `FronteggAuth` to **adopt tokens returned by `me()`**, and to fetch fresh user data on refresh when the JWT `tenantId` no longer matches the cached user; social login now also uses the potentially re-refreshed tokens. The demo `Frontegg.plist` config is updated (base URL/client ID).
> 
> <sup>Written by [Cursor Bugbot](https://cursor.com/dashboard?tab=bugbot) for commit 9a3259cff2d042c468ea169dc3fd6c95b7410512. This will update automatically on new commits. Configure [here](https://cursor.com/dashboard?tab=bugbot).</sup>
<!-- /CURSOR_SUMMARY -->
<!-- CURSOR_SUMMARY -->
> [!NOTE]
> **Low Risk**
> Low risk change limited to CI workflow behavior, but it could affect automated release PR creation if the action’s v8 defaults/inputs differ from v3.5.1.
> 
> **Overview**
> Updates the release automation workflow to use `peter-evans/create-pull-request@v8` instead of `v3.5.1` when creating the post-merge release pull request.
> 
> <sup>Written by [Cursor Bugbot](https://cursor.com/dashboard?tab=bugbot) for commit ce0385e08fd48f4dd43c6dc7afd04bd79b04090b. This will update automatically on new commits. Configure [here](https://cursor.com/dashboard?tab=bugbot).</sup>
<!-- /CURSOR_SUMMARY -->
<!-- CURSOR_SUMMARY -->
> [!NOTE]
> **Medium Risk**
> Touches embedded OAuth/PKCE callback handling; incorrect flow classification could break SSO sign-in or token exchange, though the change is small and covered by new unit tests.
> 
> **Overview**
> Prevents OIDC SSO (`/oauth/account/oidc/callback`) navigation from setting `isSocialLoginFlow`, so token exchange uses the state-matched PKCE `code_verifier` from `CredentialManager` instead of the social-login verifier stored in webview localStorage.
> 
> Adds a focused `CustomWebView.resolveHostedCallbackCodeVerifier` test suite covering OIDC SSO (correct verifier source, no fallback on state mismatch) plus regressions ensuring social login behavior and fallback remain unchanged.
> 
> <sup>Written by [Cursor Bugbot](https://cursor.com/dashboard?tab=bugbot) for commit 5210af715ad564d2acfd7bead90a2833b29eff3a. This will update automatically on new commits. Configure [here](https://cursor.com/dashboard?tab=bugbot).</sup>
<!-- /CURSOR_SUMMARY -->
<!-- CURSOR_SUMMARY -->
> [!NOTE]
> **Medium Risk**
> Touches authentication/session lifecycle (logout, token refresh, OAuth callback routing) and network monitoring concurrency; regressions could strand users in offline/unauthenticated states or break social/OIDC login redirects.
> 
> **Overview**
> **Improves offline-mode correctness and race-safety** by introducing generation-based invalidation for connectivity callbacks, centralizing monitor/debounce cleanup, and adding explicit logout transition ownership (prevents stale offline transitions during logout/token changes and adds better unauthenticated-offline recovery via `recheckConnection`).
> 
> **Hardens OAuth/social login flows** by normalizing redirect-uri generation to support base-path and root callback aliases, canonicalizing social `state`, tracking/clearing pending social PKCE verifiers, adding a watchdog to recover from stalled `/oauth/account/social/success` pages, and ensuring queued OAuth-error presentation uses captured runtime settings/delegate.
> 
> **CI stability tweaks**: adds a SwiftPM artifact-cache reset step to macOS workflows and disables Xcode parallel testing for unit/E2E runs; expands unit/E2E test coverage for the new redirect/offline behaviors.
> 
> <sup>Reviewed by [Cursor Bugbot](https://cursor.com/bugbot) for commit 884a7888e051446774dec494953dfadeacb8a399. Bugbot is set up for automated code reviews on this repo. Configure [here](https://www.cursor.com/dashboard/bugbot).</sup>
<!-- /CURSOR_SUMMARY -->

## v1.2.79
- Require Swift SDK E2E workflow for release PRs
**Changed**
- Token refresh: HTTP 408, 429, and 5xx on refresh (oauth/token and tenant refresh) are treated as transient and retried via the existing offline/retry path instead of mapping to failedToRefreshToken (which cleared the session).
- Connectivity classification: isConnectivityError recognizes ApiError.refreshEndpointTransient so behavior matches other retryable failures

**Fixed**
- Intermittent logout and auth state issues when the network is poor or the API briefly returns gateway/rate-limit responses during refresh, while 401 and other non-transient failures still end the session as before.

## v1.2.78
**Entitlements support**
- Adds support for Frontegg Entitlements so apps can load and check user features and permissions.
- What’s new
- Load entitlements from the Frontegg API and cache them locally
- Check feature and permission access with `getFeatureEntitlements`, `getPermissionEntitlements`, and `getEntitlements`
- Entitlements load automatically on login and refresh; cache is cleared on logout
- Enable via `entitlementsEnabled: true` in Frontegg.plist

**Docs & demos**
- Entitlements section in README
- Entitlements UI in demo apps

## v1.2.77
Changed baseUrl and clientId for test and demo projects.
- Replace Cocao deprecated swift dependency manager
ephemeralSession fix

## v1.2.76
Fixed: "Remember MFA Device" Setting Ignored

## v1.2.75
- added login for account support

## v1.2.74
- covered bigger area with unit tests
- removed local sentry flag

## v1.2.73
Fixed regression in Microsoft URL handling for 1.2.72. Need to upgrade to 1.2.73.
Removed security package

## v1.2.72
- updated url handler for microsoft

## v1.2.71
Increased logs for sdk.
- Google redirect callback handling

## v1.2.70
- added callback for Microsoft login `/social/success`

## v1.2.69
Google: Uses shared session → shows saved accounts
Microsoft: Uses shared session → shows saved accounts

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
