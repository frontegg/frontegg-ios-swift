# APIs

The `FronteggAuth` interface provides all the core authentication functionalities for iOS apps using the Frontegg SDK. This includes login, logout, token handling, tenant switching, region management, and support for passkeys.


## FronteggAuth

### Authentication state properties

| Property | Description |
|----------|-------------|
| `accessToken` | `ReadOnlyObservableValue<String?>` – The access token. `nil` if unauthorized. |
| `refreshToken` | `ReadOnlyObservableValue<String?>` – The refresh token. `nil` if unauthorized. |
| `user` | `ReadOnlyObservableValue<User?>` – Authenticated user info. `nil` if unauthorized. |
| `isAuthenticated` | `ReadOnlyObservableValue<Bool>` – `true` if the user is logged in. |
| `isLoading` | `ReadOnlyObservableValue<Bool>` – `true` while login or logout is in progress. |
| `initializing` | `ReadOnlyObservableValue<Bool>` – `true` while SDK is initializing. |
| `showLoader` | `ReadOnlyObservableValue<Bool>` – Indicates whether loading UI should be shown. |
| `refreshingToken` | `ReadOnlyObservableValue<Bool>` – Indicates whether a token refresh is ongoing. |

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


#### `logout(_ completion: @escaping (Result<Bool, FronteggError>) -> Void)`
Logs the user out and clears session data.

- `completion`: Called after logout completes.


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

