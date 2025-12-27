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
