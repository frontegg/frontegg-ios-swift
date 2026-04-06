# APIs

The `FronteggAuth` interface provides all the core authentication functionalities for iOS apps using the Frontegg SDK. This includes login, logout, token handling, tenant switching, region management, and support for passkeys.

## FronteggApp

### Delegate and presentation properties

| Property | Description |
|----------|-------------|
| `loggerDelegate` | Convenience alias over `FeLogger.delegate`. Receives all SDK log events, is stored weakly, and is called synchronously on the originating thread. |
| `oauthErrorPresentation` | Controls OAuth failure UI. Defaults to `.toast`. Set to `.delegate` to suppress the SDK toast and render errors in app code. |
| `oauthErrorDelegate` | Weak delegate used when `oauthErrorPresentation == .delegate`. Called on the main thread with a `FronteggOAuthErrorContext`. User-cancelled OAuth flows are not reported. |

### Logger delegate

#### `FronteggLoggerDelegate`

```swift
func fronteggSDK(didLog message: String, level: FeLogger.Level, tag: String)
```

- Receives all SDK log events, including events below the configured `logLevel`.
- `trace` and `debug` messages are forwarded as-is.
- `info`, `warning`, `error`, and `critical` messages are sanitized before delivery.
- Retain your delegate in app code; the SDK stores it weakly.

#### `FeLogger.delegate`

Global logger delegate. Assign this before accessing `FronteggApp.shared` if you
need bootstrap logs.

### OAuth error presentation

#### `FronteggOAuthErrorPresentation`

| Case | Description |
|------|-------------|
| `.toast` | The SDK shows its built-in top toast for OAuth failures. |
| `.delegate` | The SDK suppresses its built-in toast and forwards failures to `oauthErrorDelegate`. |

#### `FronteggOAuthErrorDelegate`

```swift
func fronteggSDK(didReceiveOAuthError context: FronteggOAuthErrorContext)
```

- Called on the main thread when the SDK wants the host app to render an OAuth error.
- Used only when `oauthErrorPresentation` is set to `.delegate`.
- User-cancelled OAuth flows are not reported.
- Auth flow completion callbacks still run independently of the delegate.

#### `FronteggOAuthErrorContext`

| Property | Description |
|----------|-------------|
| `displayMessage` | The user-facing message the SDK would show in toast mode. |
| `errorCode` | The raw OAuth error code, when available. |
| `errorDescription` | The decoded OAuth error description, when available. |
| `error` | The underlying `FronteggError`. |
| `flow` | Which OAuth flow failed. |
| `embeddedMode` | Whether the SDK was running in embedded mode when the error occurred. |

#### `FronteggOAuthFlow`

| Case | Description |
|------|-------------|
| `.login` | Standard login and hosted login callbacks. |
| `.socialLogin` | Social login, such as Google or GitHub. |
| `.sso` | Standard SSO flows. |
| `.customSSO` | Custom SSO flows. |
| `.apple` | Sign in with Apple. |
| `.mfa` | MFA verification flows. |
| `.stepUp` | Step-up authentication flows. |
| `.verification` | Verification or email confirmation flows. |

## FronteggAuth

### Authentication state properties

| Property | Description |
|----------|-------------|
| `accessToken` | `ReadOnlyObservableValue<String?>` – The access token. `nil` if unauthorized. |
| `refreshToken` | `ReadOnlyObservableValue<String?>` – The refresh token. `nil` if unauthorized. |
| `user` | `ReadOnlyObservableValue<User?>` – Authenticated user info. `nil` if unauthorized. |
| `isAuthenticated` | `ReadOnlyObservableValue<Bool>` – `true` if the user is logged in. |
| `isLoading` | `ReadOnlyObservableValue<Bool>` – `true` while login, logout, or authenticated session transitions are in progress. |
| `initializing` | `ReadOnlyObservableValue<Bool>` – `true` while the SDK is bootstrapping or restoring session state. |
| `showLoader` | `ReadOnlyObservableValue<Bool>` – Indicates whether `FronteggWrapper` should keep showing loader UI. |
| `refreshingToken` | `ReadOnlyObservableValue<Bool>` – Indicates whether a token refresh is ongoing. |
| `appLink` | `ReadOnlyObservableValue<Bool>` – Indicates that the SDK is in an app-link callback transition. |
| `isOfflineMode` | `ReadOnlyObservableValue<Bool>` – `true` when the SDK has committed to offline mode for the current session state. When authenticated, the app should usually stay in the authenticated area. When unauthenticated and offline mode is enabled, the host app can route to a custom no-connection screen. |
| `lastAttemptReason` | `AttemptReasonType?` – The reason for the last token refresh attempt result: `.noNetwork` (connectivity error) or `.unknown` (other error). `nil` after a successful refresh. |

## Configuration properties

| Property | Description |
|----------|-------------|
| `baseUrl` | Frontegg workspace base URL. |
| `clientId` | Client ID for your application. |
| `applicationId` | Optional: Application ID if multi-app support is enabled. |
| `isMultiRegion` | `true` if multi-region mode is enabled. |
| `regions` | List of region configurations. |
| `selectedRegion` | The currently active region. |
| `isEmbeddedMode` | Whether the SDK uses embedded login UI. |
| `useAssetsLinks` | Whether asset links are enabled. |
| `useChromeCustomTabs` | Whether Chrome Custom Tabs are used (Android-only). |
| `mainActivityClass` | Reference to the main activity class (Android-only). |

## Methods

### User authentication

#### `login(_ completion: FronteggAuth.CompletionHandler? = nil, loginHint: String? = nil)`
Logs in the user. This will open the Frontegg login page in either an embedded webview or a system browser, depending on your configuration.

- `completion`: Optional. Called when login finishes.
- `loginHint`: Optional. Pre-fills the login email.


#### `logout(clearCookie: Bool = true, _ completion: FronteggAuth.LogoutHandler? = nil)`
Logs the user out and clears session data.

- `clearCookie`: Whether to remove matching hosted-session cookies from `WKHTTPCookieStore`.
- `completion`: Called after logout finalization completes.

When `enableOfflineMode` is `true`, the final unauthenticated screen depends on connectivity after logout:

- if connectivity is available, the app should settle on the login screen
- if the user logs out while offline, `isOfflineMode` may remain `true` so the app can render its custom unauthenticated offline screen

#### `logout()`
Convenience overload for `logout(clearCookie: true, ...)`.


### Account (tenant) management

#### `switchTenant(tenantId: String, _ completion: FronteggAuth.CompletionHandler? = nil)`
Switches the current user's active tenant. Make sure to retrieve the list of available tenant IDs from the current user session.

- `tenantId`: The tenant to switch to.
- `completion`: Optional. Called after switch completes.


### Token management

#### `refreshTokenIfNeeded(attempts: Int = 0) -> Bool`
Refreshes the access token if needed.

- `attempts`: Retry count. Defaults to 0.
- **Returns**: `true` if refresh was successful, `false` otherwise.

#### `getOrRefreshAccessTokenAsync() async throws -> String?`
Returns a valid access token for use in API calls. If the current token is near expiry, attempts to refresh it.

When `enableOfflineMode` is `true` and the device is offline, returns the cached access token without attempting a network refresh. Returns `nil` if no cached token is available. The cached token may already be expired, which is expected while the app is offline.

- **Returns**: A valid access token string, or `nil` if unavailable.
- **Throws**: `FronteggError.authError(.failedToAuthenticate)` after exhausting retries (online only).

#### `getOrRefreshAccessToken(_ completion: @escaping FronteggAuth.AccessTokenHandler)`
Callback-based version of `getOrRefreshAccessTokenAsync()`.

- `completion`: Called with `.success(token)` or `.failure(error)`.

#### `recheckConnection()`
Triggers a manual connectivity recovery attempt for custom offline UI flows.

Call this from the Retry button on your app-owned offline screen. If network connectivity is back, the SDK will try to resume normal online operation.


### Passkeys authentication

#### `loginWithPasskeys(_ completion: FronteggAuth.CompletionHandler? = nil)`
Logs in the user using a previously registered passkey.

- `completion`: Optional callback with result.

#### `registerPasskeys(_ completion: FronteggAuth.ConditionCompletionHandler? = nil)`
Registers a new passkey for the current user. Passkeys enable seamless, passwordless login with biometric authentication.

- `completion`: Optional callback after registration.

### Step-Up

#### `stepUp(_ completion: FronteggAuth.CompletionHandler? = nil)`
Triggers the step-up authentication process. Typically involves MFA or other user verification.

#### `isSteppedUp(maxAge: TimeInterval) -> Bool`
Checks whether the user has already completed a step-up authentication and is allowed to proceed.


### Authorization requests

Use these methods with tokens obtained from identity-server APIs (e.g. `POST /frontegg/identity/resources/users/v1/signUp`).

#### `suspend fun requestAuthorizeAsync(refreshToken: String, deviceTokenCookie: String? = nil) -> User`
Async method to authorize silently using a refresh token.

- `refreshToken`: Token to validate (from identity-server, e.g. sign-up response).
- `deviceTokenCookie`: Optional device identifier.
- **Returns**: `User` on success.
- **Throws**: `FronteggError` on failure.


#### `fun requestAuthorize(refreshToken: String, deviceTokenCookie: String? = nil, _ completion: @escaping FronteggAuth.CompletionHandler)`
Requests authorization for the current user session.

- `refreshToken`: Token to validate (from identity-server, e.g. sign-up response).
- `deviceTokenCookie`: Optional device ID.
- `completion`: Callback with result.
