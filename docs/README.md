# Frontegg iOS SDK

![Frontegg_iOS_SDK (Swift)](/images/frontegg-swift.png)

Authentication and user management for your iOS app, in a few lines of Swift.

[Frontegg](https://frontegg.com/) is a self-served user management platform for modern SaaS
applications. This SDK brings hosted login, SSO, MFA, passkeys, RBAC and multi-tenancy to iOS —
and keeps sessions alive by refreshing tokens in the background, so you never handle a token
yourself.

**Requirements:** iOS 14+ · Swift 5.3+

---

## Install

Add the package in Xcode via **File → Add Packages**, using:

```
https://github.com/frontegg/frontegg-ios-swift
```

Or declare it in a `Package.swift` manifest:

```swift
dependencies: [
    .package(url: "https://github.com/frontegg/frontegg-ios-swift.git", from: "1.3.19")
]
```

The [releases page](https://github.com/frontegg/frontegg-ios-swift/releases) lists the current version.

## Quick start

**1. Allow the redirect URLs.** In the Frontegg Portal, under **[ENVIRONMENT] → Authentication →
Login method**, make sure hosted login is on and add:

```
{{IOS_BUNDLE_IDENTIFIER}}://{{FRONTEGG_BASE_URL}}/ios/oauth/callback
{{FRONTEGG_BASE_URL}}/oauth/authorize
```

**2. Add `Frontegg.plist`** to your project root. Your domain and client ID are in the Portal under
**[ENVIRONMENT] → Keys & domains**.

```xml
<plist version="1.0">
  <dict>
    <key>baseUrl</key>
    <string>https://{{FRONTEGG_BASE_URL}}</string>
    <key>clientId</key>
    <string>{{FRONTEGG_CLIENT_ID}}</string>
  </dict>
</plist>
```

**3. Wrap your root view.**

```swift
import SwiftUI
import FronteggSwift

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            FronteggWrapper {
                MyApp()
            }
        }
    }
}
```

**4. Read the authentication state** anywhere below it.

```swift
struct MyApp: View {
    @EnvironmentObject var fronteggAuth: FronteggAuth

    var body: some View {
        if fronteggAuth.isAuthenticated {
            MainAppView()
        } else {
            Button("Login") { fronteggAuth.login() }
        }
    }
}
```

That is a working login. Building with UIKit instead? See the
[Get Started guide](https://ios-swift-guide.frontegg.com/#/getting-started).

## Documentation

| Guide | What it covers |
| --- | --- |
| [Get Started](https://ios-swift-guide.frontegg.com/#/getting-started) | SwiftUI and UIKit integration, end to end |
| [Setup](https://ios-swift-guide.frontegg.com/#/setup) | Detailed configuration |
| [API Reference](https://ios-swift-guide.frontegg.com/#/api) | Every method the SDK exposes |
| [Usage Examples](https://ios-swift-guide.frontegg.com/#/usage) | Common implementation patterns |
| [Advanced Topics](https://ios-swift-guide.frontegg.com/#/advanced) | Multi-region, multi-app, passkeys, step-up, entitlements, logging |
| [Offline Mode](https://ios-swift-guide.frontegg.com/#/offline-mode) | Custom offline UI, reconnect behaviour, logout expectations |

Full platform documentation lives at [developers.frontegg.com](https://developers.frontegg.com).

## Example apps

Six runnable projects, each a complete integration:

[Hosted](https://github.com/frontegg/frontegg-ios-swift/tree/master/demo) ·
[Embedded](https://github.com/frontegg/frontegg-ios-swift/tree/master/demo-embedded) ·
[UIKit](https://github.com/frontegg/frontegg-ios-swift/tree/master/demo-uikit) ·
[Application-Id](https://github.com/frontegg/frontegg-ios-swift/tree/master/demo-application-id) ·
[Multi-Region](https://github.com/frontegg/frontegg-ios-swift/tree/master/demo-multi-region) ·
[Auto-Login](https://github.com/frontegg/frontegg-ios-swift/tree/master/demo-auto-login)

## Support

No Frontegg account yet? [Sign up free](https://portal.us.frontegg.com/signup).

Questions or something broken? Reach the team at
[support.frontegg.com](https://support.frontegg.com/frontegg/directories), or
[open an issue](https://github.com/frontegg/frontegg-ios-swift/issues).

Licensed under the [MIT License](https://github.com/frontegg/frontegg-ios-swift/blob/master/LICENSE).
