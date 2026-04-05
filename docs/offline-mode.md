# Offline Mode and Custom Offline UI

This guide explains how to integrate `enableOfflineMode` with an app-owned offline screen and how to validate the expected behavior in offline, reconnect, and logout scenarios.

Use this page when validating a host-app integration with:

- custom unauthenticated offline UI
- authenticated offline behavior
- reconnect and token recovery
- logout behavior while online or offline
- differences between the previous baseline behavior and the current behavior

## What Did Not Change

There is no breaking public API change in offline-mode UI wiring between the previous baseline and the current SDK behavior.

The host app still uses the same public contract:

- `enableOfflineMode`
- `isAuthenticated`
- `isOfflineMode`
- `isLoading`
- `initializing`
- `showLoader`
- `appLink`
- `recheckConnection()`

No new host-app callback, delegate, plist key, or offline-screen API was added for this flow.

## Required Configuration

Enable offline mode in `Frontegg.plist`:

```xml
<key>enableOfflineMode</key>
<true/>
<key>networkMonitoringInterval</key>
<real>10</real>
```

Your root content should still be mounted inside `FronteggWrapper`, because the wrapper owns SDK bootstrap and app-link loader states.

```swift
@main
struct ExampleApp: App {
    var body: some Scene {
        WindowGroup {
            FronteggWrapper {
                RootView()
            }
        }
    }
}
```

## Required Routing Contract

Treat the SDK state as the source of truth for routing. Do not mix it with a separate app-level reachability state when deciding which authentication screen to show.

### Root routing matrix

| SDK state | Expected UI |
|----------|-------------|
| `initializing == true`, `showLoader == true`, or `appLink == true` | `FronteggWrapper` loader |
| `isLoading == true` | App loader |
| `isAuthenticated == true` and `user != nil` | Normal authenticated app UI |
| `isAuthenticated == true` and `user == nil` | Authenticated offline fallback UI, not login |
| `isAuthenticated == false` and `isOfflineMode == true` | App-owned custom offline UI |
| `isAuthenticated == false` and `isOfflineMode == false` | Login UI |

### Quick interpretation

- `isAuthenticated == true` means the user is still considered logged in.
- `user` may be `nil` or non-`nil` while offline.
- `isOfflineMode == true` does not automatically mean "show the offline login screen".
- The custom unauthenticated offline page is only for `isAuthenticated == false && isOfflineMode == true`.

### Reference SwiftUI implementation

```swift
struct RootView: View {
    @EnvironmentObject var fronteggAuth: FronteggAuth

    var body: some View {
        if fronteggAuth.isLoading {
            LoaderView()
        } else if fronteggAuth.isAuthenticated {
            if let _ = fronteggAuth.user {
                UserPage()
            } else {
                AuthenticatedOfflineView()
            }
        } else if fronteggAuth.isOfflineMode {
            NoConnectionPage()
        } else {
            LoginPage()
        }
    }
}

struct NoConnectionPage: View {
    @EnvironmentObject private var fronteggAuth: FronteggAuth

    var body: some View {
        VStack {
            Text("No Connection")
            Button("Retry") {
                fronteggAuth.recheckConnection()
            }
        }
    }
}
```

## Offline UI Examples

These examples are the easiest way to validate whether the app is wired correctly.

### Example 1: Authenticated offline with cached user

State:

- `isAuthenticated == true`
- `isOfflineMode == true`
- `user != nil`

Expected UI:

- stay inside the app
- show the normal authenticated screen
- optionally show an offline banner or badge

```swift
if fronteggAuth.isAuthenticated, fronteggAuth.isOfflineMode, fronteggAuth.user != nil {
    UserPage()
}
```

### Example 2: Authenticated offline without cached user

State:

- `isAuthenticated == true`
- `isOfflineMode == true`
- `user == nil`

Expected UI:

- stay inside the app
- do not show login
- do not show the unauthenticated offline page
- show an authenticated offline fallback view

```swift
if fronteggAuth.isAuthenticated, fronteggAuth.user == nil {
    AuthenticatedOfflineView()
}
```

```swift
struct AuthenticatedOfflineView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Authenticated Offline")
                .font(.headline)
            Text("User details will load when connectivity returns.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
```

### Example 3: Unauthenticated offline

State:

- `isAuthenticated == false`
- `isOfflineMode == true`

Expected UI:

- show the app-owned custom offline page
- do not show the login page

```swift
if !fronteggAuth.isAuthenticated && fronteggAuth.isOfflineMode {
    NoConnectionPage()
}
```

### Example 4: Retry button on the custom offline page

```swift
struct NoConnectionPage: View {
    @EnvironmentObject private var fronteggAuth: FronteggAuth

    var body: some View {
        VStack(spacing: 16) {
            Text("No Connection")
            Button("Retry") {
                fronteggAuth.recheckConnection()
            }
        }
    }
}
```

### Critical rules

- Gate session UI on `isAuthenticated`, not on `user != nil`.
- Show the custom unauthenticated offline page only when `isAuthenticated == false && isOfflineMode == true`.
- Keep authenticated users inside the authenticated area even when `isOfflineMode == true`.
- Allow both `user == nil` and `user != nil` inside authenticated offline mode.
- Keep the retry button wired to `recheckConnection()`.
- Do not drive login-vs-offline routing from a separate reachability library unless it is strictly diagnostic.

## Expected Offline Behavior

### Cold launch with no session

When `enableOfflineMode == true` and no user session exists:

- online startup should settle on the login screen
- offline startup should settle on the custom unauthenticated offline screen
- transient probe failures should not permanently blink or stick the offline screen

When `enableOfflineMode == false`:

- the app should go straight to login
- custom offline UI should not appear

### Authenticated connectivity loss

When the user is already authenticated and connectivity is lost:

- `isAuthenticated` remains `true`
- `isOfflineMode` becomes `true`
- the app should keep the user in the authenticated area
- `getOrRefreshAccessTokenAsync()` returns the cached access token if one exists
- the cached access token may already be expired, which is expected while offline

If the user profile was not cached before connectivity was lost, `user` may be `nil` while `isAuthenticated` is still `true`. That is why authenticated routing must not depend only on `user != nil`.

### Reconnect

When connectivity returns:

- the SDK attempts to refresh tokens and restore normal online state
- `isOfflineMode` should clear after recovery
- the authenticated user should remain in the app if the session is still valid

### Logout

When offline mode is enabled:

- online logout should settle on the login screen
- logout while already offline should settle on the app-owned unauthenticated offline screen
- reconnect after offline logout should return the user to the login screen without requiring an app restart

The host app should never need to restart to escape a stale offline screen.

## Cached Artifact Restore Rules

When the app restarts without connectivity, the SDK restores as much authenticated state as the cached artifacts allow:

| Cached artifacts | Expected restore |
|------------------|------------------|
| Access token + refresh token | Authenticated offline |
| Access token only | Authenticated offline, no refresh capability until reconnect |
| Refresh token + cached user profile | Authenticated offline, can refresh when reconnect happens |
| Refresh token only, no cached user profile | Unauthenticated offline, artifacts preserved for reconnect |
| No tokens | Unauthenticated |

## Common Integration Mistakes

These are the most common causes of wrong offline UI behavior in host apps:

- Showing login whenever `user == nil`, even if `isAuthenticated == true`
- Showing the custom offline page whenever `isOfflineMode == true`, even if the user is still authenticated
- Driving routing from a second reachability flag instead of the SDK state
- Rendering the hosted login web UI underneath the custom offline page instead of switching root branches
- Leaving a gap in the root router where no loader, login, offline page, or authenticated page is rendered
- Treating a transient logout or reconnect transition as a final state

## Troubleshooting Customer Symptoms

### Logging out while offline shows the default hosted Frontegg offline screen

Check:

- `enableOfflineMode == true`
- the app switches to the custom offline page when `isAuthenticated == false && isOfflineMode == true`
- the custom offline page lives in app code, outside the hosted login web UI

Expected current behavior:

- after offline logout, the SDK should preserve unauthenticated offline mode and the app should render its custom offline page

### The custom offline screen appears during an online logout and stays until restart

Check:

- the app is not using its own reachability state to force the offline page
- the app routes only from SDK auth state
- the login screen branch is available immediately when `isAuthenticated == false && isOfflineMode == false`

Expected current behavior:

- online logout should settle on login, not a sticky offline screen

### Toggling airplane mode during logout causes a blank screen that never recovers

Check:

- the root router always has an exhaustive branch for loader, authenticated, unauthenticated offline, or login
- the app does not temporarily hide all content while waiting for a custom reachability callback
- the app still renders through `FronteggWrapper`

Expected current behavior:

- logout should settle either to login or to the custom offline page, and reconnect should not require an app restart

### Diagnostic values to capture if the issue still reproduces

If a customer still sees a wrong screen, capture the runtime values of:

- `isAuthenticated`
- `isOfflineMode`
- `isLoading`
- `initializing`
- `showLoader`
- `appLink`
- whether `user` is `nil`

These values are enough to determine whether the issue is in SDK state finalization or in app routing.

## Previous Behavior vs Current Behavior

This section summarizes behavior changes that matter for custom offline UI integrations.

| Area | Earlier behavior | Current behavior | App impact |
|------|-------------------|----------------------|------------|
| Public offline UI contract | Existing contract based on `isAuthenticated`, `isOfflineMode`, and `recheckConnection()` | Same public contract | No host-app API migration required |
| Unauthenticated cold launch | More vulnerable to transient connectivity probe failures committing offline UI too early | Performs a short connectivity settlement flow before committing unauthenticated offline mode | Fewer false custom offline-screen flashes |
| Reconnect handling | Stale debounced disconnect work could still win after connectivity recovered | Pending offline debounce is canceled and stale callbacks are ignored | Less risk of `isOfflineMode` flipping back to `true` after recovery |
| Successful login or refresh | Old transient offline state could linger after authenticated success | Authenticated success clears stale offline debounce and monitoring state | Less risk of carrying offline UI state into a healthy authenticated session |
| Logout while offline | Session cleanup could finish without intentionally preserving the unauthenticated offline state | Logout explicitly preserves unauthenticated offline mode when the user was already offline | Custom offline page should now appear directly after offline logout |
| Logout while online | More vulnerable to stale monitoring or probe work affecting the final unauthenticated screen | Logout owns connectivity teardown and re-settles the unauthenticated end state | Less risk of sticky custom offline UI during online logout |
| Demo app changes | No dedicated screen markers | Added accessibility markers and sticky diagnostics | Test-only; no product integration change required |

## Validated Scenarios

The current SDK behavior is exercised against these demo-embedded scenarios:

| Scenario | Expected result |
|----------|-----------------|
| Cold launch through transient probe failures | Login appears and the custom offline screen does not blink persistently |
| Authenticated relaunch with network path unavailable | User remains authenticated and enters authenticated offline mode |
| Authenticated offline mode recovery | Reconnect clears offline mode and refreshes tokens |
| Logout while authenticated offline | App lands on the custom unauthenticated offline page |
| Offline mode disabled | Offline indicators and custom offline UI do not appear |

## Validation Checklist for App Teams

Use this checklist when comparing your app against the expected integration:

1. `enableOfflineMode` is enabled in `Frontegg.plist`.
2. The root app content is mounted inside `FronteggWrapper`.
3. The root router follows the state matrix in this guide.
4. The custom offline page renders only for `isAuthenticated == false && isOfflineMode == true`.
5. Authenticated offline users stay in the authenticated area, even if `user == nil`.
6. The retry button calls `fronteggAuth.recheckConnection()`.
7. No second reachability state overrides the SDK when choosing login vs offline UI.
8. The app never renders an empty root state during logout or reconnect.

If all eight checks are true and the issue still reproduces, capture the diagnostic values listed above together with the reproduction steps.
