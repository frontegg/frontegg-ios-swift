# Authentication and usage

Frontegg Swift SDK provides multiple authentication flows to enhance your iOS app’s user experience. Whether you prefer a native look and feel or the latest in passwordless security, the SDK offers flexible options that are easy to integrate:

* **Embedded webview**: A customizable in-app webview login experience, which is enabled by default.
* **ASWebAuthenticationSession**: A secure, system-level authentication flow introduced in iOS 12+, ideal for native user experience and strong session isolation.
* **Passkeys**: A modern, passwordless login method based on biometric authentication and WebAuthn, available on iOS 15+.

### ASWebAuthenticationSession

Starting from SDK version 1.2.9, you can switch to `ASWebAuthenticationSession` for a seamless authentication flow. To enable `ASWebAuthenticationSession`:

1. Open your Xcode project.
2. Open the `Frontegg.plist` file, which should be in the root of your Xcode project.
3. Set `embeddedMode` to `false` to enable `ASWebAuthenticationSession`. For example:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN">
<plist version="1.0">
  <dict>
    <key>baseUrl</key>
    <string>https://your-domain.frontegg.com</string>
    <key>clientId</key>
    <string>your-client-id</string>

    <!-- Set to false to use ASWebAuthenticationSession -->
    <key>embeddedMode</key>
    <false/>
  </dict>
</plist>
```

4. Use `loginWithPopup` in your app. The `loginWithPopup` method supports `ASWebAuthenticationSession` with the following parameters:

| Parameter          | Description                                                                 |
|--------------------|-----------------------------------------------------------------------------|
| `window`           | The target `UIWindow` for presentation. Defaults to the key window if `nil`. |
| `ephemeralSession` | Whether to use an ephemeral (private) session. Default is `true`.            |
| `loginHint`        | Optional login hint to pre-fill the login field.                            |
| `loginAction`      | Optional custom login action string.                                        |
| `completion`       | Callback that returns either a `User` on success or a `FronteggError` on failure. |


UIKit example:

```swift
import UIKit
import FronteggSwift

class ViewController: UIViewController {
    @IBAction func loginButtonTapped() {
        FronteggAuth.shared.loginWithPopup(window: self.view.window) { result in
            switch result {
            case .success(let user):
                print("User logged in: \(user)")
            case .failure(let error):
                print("Error logging in: \(error)")
            }
        }
    }
}
```

SwiftUI example:

```swift
import SwiftUI
import FronteggSwift

struct ContentView: View {
    @EnvironmentObject var fronteggAuth: FronteggAuth
    
    var body: some View {
        VStack {
            if fronteggAuth.isAuthenticated {
                Text("User Authenticated")
            } else {
                Button("Login") {
                    fronteggAuth.loginWithPopup()
                }
            }
        }
    }
}
```
