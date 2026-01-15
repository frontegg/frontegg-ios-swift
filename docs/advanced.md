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

The SDK can also log trace IDs from API responses to help with debugging. This is a separate feature from the log level.

To enable trace ID logging:

```xml
<key>enableTraceIdLogging</key>
<true/>
```

When enabled, trace IDs from API responses (in the `frontegg-trace-id` header) will be saved to a file `frontegg-trace-ids.log` in your project directory (or Documents directory in the simulator).


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