# Advanced options

In this guide, you'll find an overview and best practices for enabling advanced features like passkeys and multi-app configurations.

## Multi-app support

If your Frontegg workspace supports multiple apps, you need to specify which one your iOS client should use.

To enable this feature, add `applicationId` to `Frontegg.plist` as follows:

```xml
<plist version="1.0">
  <dict>
    <key>applicationId</key>
    <string>{{FRONTEGG_APPLICATION_ID}}</string>

    <key>baseUrl</key>
    <string>{{FRONTEGG_BASE_URL}}</string>

    <key>clientId</key>
    <string>{{FRONTEGG_CLIENT_ID}}</string>
  </dict>
</plist>
```

- Replace `{{FRONTEGG_APPLICATION_ID}}` with your application ID.
- Replace `{{FRONTEGG_BASE_URL}}` with the domain name from your Frontegg Portal.
- Replace `{{FRONTEGG_CLIENT_ID}}` with your Frontegg client ID.

## Login per account (custom login box)

When your Frontegg workspace uses **login per account**, each account (tenant) has its own login URL and branded login experience. To route users to a specific account’s login from the iOS app, set the account alias via config or in code.

### Enable via config (Frontegg.plist)

Add `loginOrganizationAlias` to your `Frontegg.plist` and set it to the account’s **alias** (the identifier configured in Frontegg for that account). Leave the key out or set it to an empty string for standard (non–login-per-account) login.

```xml
<key>loginOrganizationAlias</key>
<string>acme</string>
```

The SDK reads this at startup and adds `organization=<alias>` to the authorize URL for all login flows. No code changes are required.

### Set the account alias in code

You can also set `loginOrganizationAlias` on `FronteggApp` at runtime (e.g. from a deep link or tenant context). This overrides the plist value. Set it to the account’s **alias** so the SDK adds `organization=<alias>` to the authorize URL.

**Query parameter (recommended)**  
If your app knows the account from a URL or deep link (e.g. `?organization=acme`), set the alias before presenting login:

```swift
// Before showing login (e.g. when user opens a tenant-specific link)
FronteggApp.shared.loginOrganizationAlias = "acme"  // account alias from your URL/context
// Then call your usual login flow (hosted or embedded)
```

**Subdomain**  
If you use subdomains per account (e.g. `acme.yourdomain.com`), derive the alias from the host and set it the same way before login.

### Hosted vs embedded

- **Hosted login**: The authorize URL becomes `https://[YOUR_DOMAIN]/oauth/authorize?organization=[ALIAS]&...`.
- **Embedded login**: The same `organization` query parameter is included when loading the login page in the WebView.

All login entry points (hosted, embedded, social, magic link, etc.) use `FronteggApp.shared.loginOrganizationAlias` when generating the authorize URL, so you only need to set it once before starting the flow.

### Limitations

- **Switching tenants**: `switchTenant` is not supported between accounts that have custom login boxes. Users who need to use another such account must log in again (with that account’s alias set).
- If you only need different app URLs per account and not different login experiences, use [Application URL](https://developers.frontegg.com/api/tenants/accounts/tenantcontrollerv1_createtenant#applicationurl) configuration instead of custom login boxes.

## Multi-region support

If you operate across multiple regions, you can dynamically switch between environments at runtime.

### Update `Frontegg.plist` for regions

1. Remove the existing `baseUrl` and `clientId` keys.
2. Add a new array key named `regions`. This array will hold dictionaries for each region.

```xml
<plist version="1.0">
  <dict>
    <key>regions</key>
    <array>
      <dict>
        <key>key</key>
        <string>us-region</string>
        <key>baseUrl</key>
        <string>https://{{FRONTEGG_BASE_URL}}</string>
        <key>clientId</key>
        <string>{{FRONTEGG_CLIENT_ID}}</string>
      </dict>
      <!-- Add more regions here -->
    </array>
  </dict>
</plist>
```

- Replace `{{FRONTEGG_BASE_URL}}` with the domain name from your Frontegg Portal.
- Replace `{{FRONTEGG_CLIENT_ID}}` with your Frontegg client ID.

### Configure associated domains

Each region must have its domain added to the iOS app for proper redirection and authentication. For example:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.applesignin</key>
	<array>
		<string>Default</string>
	</array>
	<key>com.apple.developer.associated-domains</key>
	<array>
		<string>webcredentials:autheu.davidantoon.me</string>
		<string>applinks:autheu.davidantoon.me</string>
		<string>webcredentials:authus.davidantoon.me</string>
		<string>applinks:authus.davidantoon.me</string>
		<string>webcredentials:davidantoon.me</string>
	</array>
</dict>
</plist>
```

1. Open your project in **Xcode**.  
2. In the **Project Navigator**, click on your **project name**.  
3. Select your **target application**.  
4. Go to the **Signing & Capabilities** tab.  
5. Click **+ Capability**, then add **Associated Domains**.  
6. Under the **Associated Domains** section, click the **+** button.  
7. Add the following entries:
   ```
   applinks:your-associated-domain.com
   webcredentials:your-associated-domain.com
   ```

   For example, if your domain is `https://example.com`, add `applinks:example.com` and `webcredentials:example.com`.

8. Click **Done**.

### Implement region selection UI

The final step is to implement a user interface that allows the user to select their region. You can design this UI in any way that fits your application's needs.

**Important considerations**

- **Switching Regions**:  
  To switch regions, update the selected value in `UserDefaults`. If issues occur, re-installing the application may be required to reset stored data.

- **Data Isolation**:  
  Ensure that all data handling and API calls are region-specific. This is essential to prevent data leakage or access across different regions.


In the follwing example app, a simple picker view is used to let users choose their region.

```swift
import SwiftUI
import FronteggSwift

struct SelectRegionView: View {
    @EnvironmentObject var fronteggAuth: FronteggAuth

    var body: some View {
        VStack(alignment: .leading) {
            Text("Select your region")
                .font(.title)

            ForEach(fronteggAuth.regionData, id: \.key.self) { region in
                Button(action: {
                    FronteggApp.shared.initWithRegion(regionKey: region.key)
                }) {
                    VStack(alignment: .leading) {
                        Text("Region - \(region.key.uppercased())")
                            .font(.headline)
                        Text(region.baseUrl)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .padding()
        .navigationTitle("Region")
    }
}
```

This is what this example looks like:

|                     Select EU Region                     |                     Select US Region                     |
|:--------------------------------------------------------:|:--------------------------------------------------------:|
| ![eu-region-example.gif](./images/eu-region-example.gif) | ![us-region-example.gif](./images/us-region-example.gif) |

## Logout after reinstall

To force logout when a user reinstalls the app, update your `Frontegg.plist` file:

```xml
<plist version="1.0">
  <dict>
    <key>keepUserLoggedInAfterReinstall</key>
    <false/>
    ...
  </dict>
</plist>
```

By default `keepUserLoggedInAfterReinstall` is `true`.

## Logging

The SDK includes built-in logging capabilities to help you debug and monitor your application.

### Log Levels

The SDK supports the following log levels (from most verbose to least):

- `trace` - Detailed tracing information
- `debug` - Debug information for development
- `info` - General informational messages
- `warn` - Warning messages (default)
- `error` - Error conditions
- `critical` - Critical error conditions

### What is the difference between `trace` and `debug` (and others)?

In this SDK, the configured `logLevel` acts as a threshold. Selecting a level enables logs at that level **and all more severe levels**:

- `trace`: trace + debug + info + warn + error + critical
- `debug`: debug + info + warn + error + critical
- `info`: info + warn + error + critical
- `warn`: warn + error + critical
- `error`: error + critical
- `critical`: critical only

Practical guidance:
- Use `debug` for most troubleshooting sessions.
- Use `trace` only when you need very detailed step-by-step flow tracing (it can be noisy).

### Default Log Level

By default, the SDK uses **`warn`** log level, which means only warnings, errors, and critical messages will be logged.

### Configuring Log Level

You can configure the log level in your `Frontegg.plist` file:

```xml
<key>logLevel</key>
<string>debug</string>
```

Available values: `trace`, `debug`, `info`, `warn`, `error`, `critical`

### Trace ID Logging

When `enableSentryLogging` is enabled, the SDK automatically logs trace IDs from API responses in two ways:

1. **Sentry breadcrumbs**: Sends trace IDs to Sentry for production debugging and correlating client-side issues with server logs
2. **File-based logging**: Saves trace IDs to a local file `frontegg-trace-ids.log` in your project directory (or Documents directory in the simulator) for local development

Both features are controlled by the `enableSentryLogging` flag. When enabled, trace IDs from API responses (in the `frontegg-trace-id` header) will be:
- Sent to Sentry as breadcrumbs (useful for production debugging)
- Saved to a local file (useful for local development)

To enable trace ID logging:

```xml
<key>enableSentryLogging</key>
<true/>
```

### Sentry Max Queue Size

When `enableSentryLogging` is enabled, you can configure the maximum number of events that Sentry will cache when offline. This prevents memory abuse during extended offline periods.

```xml
<key>sentryMaxQueueSize</key>
<integer>30</integer>
```

- **Default**: `30`
- **Description**: Maximum number of events (errors, messages, breadcrumbs) that Sentry will cache locally when the device is offline. This maps to Sentry's `maxCacheItems` setting. When the cache is full, older events are dropped to make room for new ones. Sentry automatically sends cached events when the network becomes available.
- **Recommendation**: For apps with frequent offline periods, consider a lower value (e.g., `20`) to reduce memory usage. For apps that need comprehensive offline logging, you can increase it (e.g., `50`).

## Complete Frontegg.plist Configuration Reference

This section documents all available configuration keys in `Frontegg.plist`.

### Required Keys

| Key | Type | Description |
|-----|------|-------------|
| `baseUrl` | String | Your Frontegg domain (e.g., `https://app-xxxx.frontegg.com`) |
| `clientId` | String | Your Frontegg client ID |

### Optional Authentication Keys

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `applicationId` | String | `nil` | Application ID for multi-app workspaces |
| `embeddedMode` | Boolean | `true` | Use embedded webview (`true`) or system browser (`false`) for login |
| `loginWithSocialLogin` | Boolean | `true` | Enable social login (Google, GitHub, etc.) |
| `handleLoginWithCustomSocialLoginProvider` | Boolean | `true` | Enable custom social login providers |
| `handleLoginWithSocialProvider` | Boolean | `true` | Enable social provider login handlers |
| `loginWithSSO` | Boolean | `false` | Enable SSO login |
| `loginWithCustomSSO` | Boolean | `false` | Enable custom SSO login |
| `useLegacySocialLoginFlow` | Boolean | `false` | Use legacy social login flow (for backward compatibility) |
| `useAsWebAuthenticationForAppleLogin` | Boolean | `false` | Use `ASWebAuthenticationSession` for Apple Sign In |

### Session Management Keys

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `keepUserLoggedInAfterReinstall` | Boolean | `true` | Keep user logged in after app reinstall |
| `enableSessionPerTenant` | Boolean | `false` | Enable separate sessions per tenant (multi-tenancy) |
| `keychainService` | String | `"frontegg"` | Keychain service name for storing credentials |

### Offline Mode Keys

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enableOfflineMode` | Boolean | `false` | Enable offline mode - keep user logged in when network is unavailable |
| `networkMonitoringInterval` | Number | `10` | Interval (in seconds) for network status monitoring when offline mode is enabled |

### Logging Keys

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `logLevel` | String | `"warn"` | Log level: `trace`, `debug`, `info`, `warn`, `error`, `critical` |
| `enableSentryLogging` | Boolean | `true` | Enable Sentry error tracking and logging |
| `sentryMaxQueueSize` | Integer | `30` | Maximum number of events to queue when offline (Sentry) |

### UI Customization Keys

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `backgroundColor` | String | `nil` | Background color for login UI (hex format, e.g., `"#FFFFFF"`) |
| `shouldSuggestSavePassword` | Boolean | `false` | Enable iOS password autofill suggestions |

### Cookie Management Keys

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `cookieRegex` | String | `nil` | Regular expression to match cookies for deletion (e.g., `"^_fe.*\|^session.*"`) |
| `deleteCookieForHostOnly` | Boolean | `true` | Delete cookies only for the host (excluding subdomains) |

### Advanced Keys

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `lateInit` | Boolean | `false` | Enable late initialization (allows SDK to initialize without full config) |

### Multi-Region Configuration

Instead of `baseUrl` and `clientId`, you can use a `regions` array for multi-region support:

```xml
<key>regions</key>
<array>
  <dict>
    <key>key</key>
    <string>us-region</string>
    <key>baseUrl</key>
    <string>https://app-us.frontegg.com</string>
    <key>clientId</key>
    <string>your-client-id</string>
    <key>applicationId</key>
    <string>your-app-id</string>
  </dict>
  <dict>
    <key>key</key>
    <string>eu-region</string>
    <key>baseUrl</key>
    <string>https://app-eu.frontegg.com</string>
    <key>clientId</key>
    <string>your-client-id</string>
  </dict>
</array>
```

### Example Complete Configuration

```xml
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <!-- Required -->
  <key>baseUrl</key>
  <string>https://app-xxxx.frontegg.com</string>
  <key>clientId</key>
  <string>your-client-id</string>
  
  <!-- Optional: Multi-app -->
  <key>applicationId</key>
  <string>your-application-id</string>
  
  <!-- Optional: Authentication -->
  <key>embeddedMode</key>
  <true/>
  <key>loginWithSocialLogin</key>
  <true/>
  
  <!-- Optional: Session Management -->
  <key>keepUserLoggedInAfterReinstall</key>
  <true/>
  <key>enableSessionPerTenant</key>
  <true/>
  
  <!-- Optional: Offline Mode -->
  <key>enableOfflineMode</key>
  <true/>
  <key>networkMonitoringInterval</key>
  <real>10</real>
  
  <!-- Optional: Logging -->
  <key>logLevel</key>
  <string>debug</string>
  <key>enableSentryLogging</key>
  <true/>
  <key>sentryMaxQueueSize</key>
  <integer>30</integer>
  
  <!-- Optional: UI Customization -->
  <key>backgroundColor</key>
  <string>#FFFFFF</string>
  
  <!-- Optional: Cookie Management -->
  <key>cookieRegex</key>
  <string>^_fe.*|^session.*</string>
  <key>deleteCookieForHostOnly</key>
  <true/>
</dict>
</plist>
```

## Passkeys authentication (iOS 15+)

Passkeys provide a seamless, passwordless login experience using WebAuthn and platform-level biometric authentication.

**Prerequisites**

1. **iOS Version**: Ensure your project targets **iOS 15 or later** to support the necessary WebAuthn APIs.
2. **Associated Domain**: Configure your app's associated domains to enable passkeys functionality.
3. **Frontegg SDK Version**: Use Frontegg iOS SDK version **1.2.24 or later**.

### Configure associated domains in Xcode

1. Open your project in **Xcode**
2. Go to your **target** settings
3. Open the **Signing & Capabilities** tab
4. Click the **+ Capability** button and add **Associated Domains**
5. Under **Associated Domains**, click the **+** and add: `webcredentials:your-domain.com`. For example, if your domain is `https://example.com`, use `webcredentials:example.com`.

### Host the `.well-known/webauthn` file

1. On your server, create a JSON file at the following location: `https://your-domain.com/.well-known/webauthn`.
2. Use the structure below:

```json
{
  "origins": [
    "https://your-domain.com",
    "https://subdomain.your-domain.com"
  ]
}
```

3. Ensure this file is publicly accessible (HTTP 200 OK).

### Test domain association

Verify that your associated domain configuration works using Apple's [Associated Domains Validator](https://developer.apple.com/contact/request/associated-domains).

### Register passkeys

Call this method from your app to enable passkeys registration for a user:

```swift
import FronteggSwift

func registerPasskeys() {
    if #available(iOS 15.0, *) {
        FronteggAuth.shared.registerPasskeys()
    } else {
        print("Passkeys are only supported on iOS 15 or later.")
    }
}
```

### Login with passkeys

To log users in using a stored passkey:

```swift
import FronteggSwift

func loginWithPasskeys() {
    if #available(iOS 15.0, *) {
        FronteggAuth.shared.loginWithPasskeys { result in
            switch result {
            case .success(let user):
                print("User logged in: \(user)")
            case .failure(let error):
                print("Error logging in: \(error)")
            }
        }
    } else {
        print("Passkeys are only supported on iOS 15 or later.")
    }
}
```

## Step-up authentication

Step-Up Authentication allows you to temporarily elevate a user's authentication level to perform sensitive actions. This is useful for operations like updating credentials, accessing confidential data, or performing secure transactions.


#### `stepUp`

Starts the step-up authentication flow. This will usually trigger a secondary authentication method ( e.g. biometric, MFA, etc).

`maxAge` (optional): How long the elevated session is considered valid, in seconds.

`completion`: A closure called after authentication finishes. If step-up fails, it receives an error.

```
Task {
    await FronteggAuth.shared.stepUp(maxAge: 300) { error in
        if let error = error {
            print("Step-up failed: \(error.localizedDescription)")
            return
        }

        // Authentication successful, continue with the secure action
        self.performSensitiveAction()
    }
}
```

#### `isSteppedUp`

This method hecks whether the user has recently completed a step-up authentication and whether it is still valid.


```
let isSteppedUp = FronteggAuth.shared.isSteppedUp(maxAge: 300) // 300 seconds = 5 minutes

if isSteppedUp {
    // Proceed with secure operation
} else {
    // Trigger step-up flow
}
```

**Example**
```
func performSensitiveFlow() {
    let isElevated = FronteggAuth.shared.isSteppedUp(maxAge: 300)

    if isElevated {
        performSensitiveAction()
    } else {
        Task {
            await FronteggAuth.shared.stepUp(maxAge: 300) { error in
                if let error = error {
                    showAlert("Authentication Failed", message: error.localizedDescription)
                    return
                }
                performSensitiveAction()
            }
        }
    }
}

func performSensitiveAction() {
    // Proceed with a high-security task
    print("Secure action performed.")
}
```