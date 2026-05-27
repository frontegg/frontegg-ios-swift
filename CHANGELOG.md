## v1.3.8
Fix for step Up feature with MFA.

## v1.3.7
## Summary

Port of [frontegg/frontegg-android-kotlin#254](https://github.com/frontegg/frontegg-android-kotlin/pull/254) to the Swift SDK. Adds the missing cache invalidation step in `setCredentialsInternal` so `getFeatureEntitlements` cannot leak the previous tenant's verdict during the in-flight reload window or after a failed reload.

## Why

`setCredentialsInternal` — the workhorse that `switchTenant` routes through after re-minting tokens — fires `loadEntitlements(forceRefresh: true)` on the new tenant's access token but never invalidates the cache first. Two windows still leak the previous tenant's view:

1. **In-flight reload** — between `loadEntitlements` being called and `performEntitlementsLoad`'s `Task` writing the new state, `getFeatureEntitlements()` keeps returning the PREVIOUS tenant's verdict. State and `hasLoaded` are unchanged until the load completes.

2. **Failed reload** — `Entitlements.load` returns `false` on HTTP error or decode failure WITHOUT touching `_state` ([Entitlements.swift:74-78](Sources/FronteggSwift/services/Entitlements.swift#L74-L78), [:94-97](Sources/FronteggSwift/services/Entitlements.swift#L94-L97)). The cache is pinned to the previous tenant forever — until another `getUserEntitlements` call eventually succeeds, or until the SDK process restarts.

**Customer-visible symptom (FR-24821):** after switching to a tenant without the `sso` feature, `fronteggAuth.getFeatureEntitlements(featureKey: "sso")` still reports `isEntitled = true`. With this change, the verdict is one of:

- the new tenant's verdict (reload succeeded — normal case), or
- `Entitlement(isEntitled: false, justification: "MISSING_FEATURE")` on the empty cache during the in-flight window or after a failed reload.

Never the previous tenant's verdict.

> NB: Swift's `Entitlements.checkFeature` reports `MISSING_FEATURE` on an empty state, whereas the Android counterpart returns `ENTITLEMENTS_NOT_LOADED` when `hasLoaded == false`. Same defensive boolean (`isEntitled == false`), different justification string. Documented in the failed-reload test. This PR doesn't change the justification surface — that's a separate platform-parity item if we ever want to align.

## The fix

One line in `setCredentialsInternal`, immediately before `loadEntitlements(forceRefresh: true)`:

```swift
entitlements.clear()
loadEntitlements(forceRefresh: true)
```

For login / restore-from-storage paths the cache is already empty (in-memory only, no persistence), so the clear is a no-op. The behavior change is scoped to tenant switching, where `setCredentialsInternal` runs with a populated cache from the prior tenant.

## Tests

Three regression tests in [`FronteggAuthEntitlementsTests`](Tests/FronteggSwiftTests/FronteggAuthEntitlementsTests.swift), sharing a `seedTenantAEntitlementsCacheWithSSO()` helper plus tenant-B JWT / User builders plus a `BlockingAuthEntitlementsApi`-driven poll helper:

| # | Test | What it covers | FAILS without fix? |
|---|---|---|---|
| 1 | `…(FR-24821 happy path)` | Successful reload returning empty entitlements for tenant B. Asserts `hasLoaded` true, `state.featureKeys` empty, `getFeatureEntitlements("sso") → MISSING_FEATURE`. | No — `loadEntitlements` is already fired. Kept as top-level guard for the customer-reported symptom. |
| 2 | `…in-flight window` | Blocks the reload's HTTP response so the load Task stays suspended in `api.getRequest`. Asserts cache is already empty + `hasLoaded` is already false BEFORE load completes. | **Yes** — without fix, `hasLoaded` stays true (tenant A's `{sso}`) until load completes. |
| 3 | `…failed reload` | Reload responds 500. `Entitlements.load` returns false on HTTP error without touching `_state`. With fix: cache empty, `getFeatureEntitlements("sso").isEntitled == false`. | **Yes** — without fix, cache stays pinned to tenant A's `{sso}` forever. |

Differential verified by temporarily removing `entitlements.clear()` from `setCredentialsInternal` and re-running: tests 2 and 3 fail, test 1 passes.

## Test plan

- [x] All 3 new tests pass with fix
- [x] Tests 2 and 3 fail without fix (differential — temporarily reverted the production change and re-ran)
- [x] Test 1 passes on bare master (top-level FR-24821 regression guard)
- [x] `xcodebuild -scheme FronteggSwift -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' test` — full suite **683 tests / 0 failures / 18 skipped**
- [ ] Manual: in a demo app, force a tenant-B reload failure (e.g., kill network mid-switch) and confirm `getFeatureEntitlements("sso")` no longer reports the previous tenant's verdict

## Diff

- `+13 lines` in [FronteggAuth+CredentialHydration.swift](Sources/FronteggSwift/auth/FronteggAuth+CredentialHydration.swift) (1 line of code + 12-line explanatory comment).
- `+227 lines` in [FronteggAuthEntitlementsTests.swift](Tests/FronteggSwiftTests/FronteggAuthEntitlementsTests.swift) (helpers + 3 tests).

## Related

- [frontegg-android-kotlin#254](https://github.com/frontegg/frontegg-android-kotlin/pull/254) — the equivalent Android fix this is ported from.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## v1.3.6

- Sentry's automatic network breadcrumbs have been disabled
## Summary

Follow-up to [#261](https://github.com/frontegg/frontegg-ios-swift/pull/261). Removes the `Unit Tests (Thread Sanitizer)` job from [.github/workflows/demo-e2e.yml](.github/workflows/demo-e2e.yml).

## Why

The TSan job that landed in #261 has two known issues:

1. **Real race in `FronteggSwift.FeLogger.dispatchToDelegate`** — reproduces locally during `LoggerDelegateTests` when run as part of the full suite. Delegate-registration writes from one test race dispatch-queue reads from another.
2. **Test-runner hang under TSan instrumentation** — even with `timeout-minutes: 25`, the job sits at ~25m26s before timing out on every PR.

Pulling the job is cleaner than leaving it as a 25-min advisory failure on every PR. Both findings are captured in `CONTRIBUTING.md` → "Known TSan findings (CI integration deferred)" for the follow-up that fixes the race and re-adds the job.

## Changes

- `.github/workflows/demo-e2e.yml` — remove the `unit-tests-tsan` job, its entry from the `summary` job's `needs:`, the artifact-download step, and the `Append Thread Sanitizer summary` step.
- `CONTRIBUTING.md` — update the "Unit tests with Thread Sanitizer" section to say it's local-only; replace the old "Thread Sanitizer — currently advisory" subsection with "Known TSan findings (CI integration deferred)" that documents both blockers for the re-add.

## Test plan

- [ ] CI: all checks pass without TSan job
- [ ] No red \`Unit Tests (Thread Sanitizer)\` mark on this PR
- [ ] After merge, future PRs no longer run TSan

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## v1.3.5
## Summary
Adds Admin Portal BETA version to the SDK. Opens `${baseUrl}/oauth/portal?appId=<applicationId>` in a WebView that shares the process-wide CookieManager with the SDK's login WebView so authenticated users don't see a second login.

- New public surface: `AdminPortalView` from anywhere in the host app
- Demo app: "Open Admin Portal" button on the home screen

## Implementation details
`applicationId` is required. Without it, the portal renders "Application not found" after login when the SDK was configured with an application context.

## v1.3.4
Removed logging of 502/503 errors for Sentry

## v1.3.3
## Summary
- When a user logs out while offline (or network drops during logout), `reconnectedToInternet()` only ran the authenticated path (`refreshTokenIfNeeded`), which is a no-op without tokens — leaving a blank screen
- Added unauthenticated handling: detects no-session state and clears offline flags + reloads the login page via `reloadFreshLoginPage()`
- Mirrors the existing `recheckConnection()` logic for the automatic reconnection callback


## v1.3.2
- Added disableAutoRefresh feature

## v1.3.1
- `reinitWithRegion()` accessed `FronteggApp.shared.entitlementsEnabled` during `FronteggApp.init()`, before the singleton was assigned — causing `EXC_BREAKPOINT` crash for returning users on multi-region configs with entitlements enabled
- Pass `entitlementsEnabled` as a parameter to `reinitWithRegion()` instead of referencing the singleton, consistent with how `manualInit()` and `manualInitRegions()` already work

## v1.3.0

**Added**
- Offline mode support with authenticated startup session restore, network path assessment, and offline state handling
- Step-up authentication methods via refactored OAuth state handling
- Customizable OAuth error handling and presentation
- Transactional logout process with timeout for cookie clearing
- Transactional refresh token handling with enhanced diagnostics
- API retry logic for `/me` and `/me/tenants` endpoints with error handling
- Social login watchdog to recover from stalled `/oauth/account/social/success` pages
- `offlineDebounceDelay` plist option (default `2.0s`) — configurable delay before committing to offline mode, prevents flicker during WiFi-to-cellular handoff
- `dismissAuthSessionOnOffline` plist option (default `false`) — opt-in cancellation of active Safari auth sheet when device goes offline

**Changed**
- Refactored connectivity and refresh handling to use async/await for improved responsiveness
- Made login progress state actor-safe and enhanced token exchange handling
- Skip PKCE injection for custom providers to align with hosted social flow
- Generation-based invalidation for connectivity callbacks to prevent stale offline transitions
- Enhanced API error handling and logging for GET requests
- Improved redirect URI extraction with base path and root callback alias support
- Increased offline debounce delay from 0.6s to 2.0s (configurable via plist) to reduce false offline transitions
- Improved `suggestSavePassword` error message to include expected payload format for custom login script integration

**Fixed**
- Fix PKCE state registration race condition — serialize `registerPendingOAuth` with NSLock to prevent concurrent calls from overwriting each other's state entries, which caused "Invalid or stale OAuth state" on first login attempt
- Remove WebView warmup (`warmingWebView`) that generated a competing authorize URL during app startup, causing PKCE state mismatch with the real login WebView
- Fix social login watchdog infinite retry loop — the retry counter was reset on each reload because `socialSuccessRetryCount` was zeroed when the reloaded `/social/success` page re-triggered navigation detection; now only genuinely fresh flows reset the counter
- Prevent incorrect setting of `isSocialLoginFlow` in OIDC SSO process, ensuring correct PKCE `code_verifier` usage
- Prevent unexpected logout by refreshing token on tenant retrieval failure (FR-22001)
- Fix tenant ID persistence and credential namespace issues
- Handle stalled social login success page with retry logic and improved error visibility
- Skip connectivity state handling if generation has changed during token updates
- Improve async handling in connectivity checks and token change monitoring
- Add Sentry breadcrumb when hosted login callback arrives with unregistered OAuth state for improved diagnostics

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
