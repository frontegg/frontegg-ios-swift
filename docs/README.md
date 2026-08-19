<p align="center">
  <img src="https://raw.githubusercontent.com/frontegg/frontegg-ios-swift/master/images/frontegg-swift.png" alt="Frontegg iOS SDK" width="640" />
</p>

<h1 align="center">Frontegg iOS SDK</h1>

<p align="center">
  <strong>Authentication and user management for your iOS app — in a few lines of Swift.</strong>
</p>

<p align="center">
  <a href="https://github.com/frontegg/frontegg-ios-swift/releases"><img src="https://img.shields.io/github/v/release/frontegg/frontegg-ios-swift?label=release&color=6c47ff" alt="Latest release" /></a>
  <img src="https://img.shields.io/badge/platform-iOS%2014%2B-lightgrey" alt="iOS 14+" />
  <img src="https://img.shields.io/badge/Swift-5.3%2B-orange" alt="Swift 5.3+" />
  <img src="https://img.shields.io/badge/SPM-compatible-brightgreen" alt="Swift Package Manager" />
  <a href="https://github.com/frontegg/frontegg-ios-swift/blob/master/LICENSE"><img src="https://img.shields.io/github/license/frontegg/frontegg-ios-swift?color=blue" alt="MIT License" /></a>
</p>

---

[Frontegg](https://frontegg.com/) is a self-served user management platform for modern SaaS
applications. Drop this SDK in and your app gets a production login screen, a live session, and a
user object — without you writing an auth flow or touching a token.

| | |
| --- | --- |
| **Hosted or embedded login** | Frontegg's login box in a webview, or your own UI on top of the API |
| **Every method your tenants need** | Email, social, SSO, magic link, passkeys, MFA and step-up |
| **Sessions that stay alive** | Tokens refresh in the background; offline mode keeps users working without a connection |
| **Built for multi-tenant SaaS** | Multi-tenancy, RBAC, entitlements, multi-region and multi-app support |

---

## Install

In Xcode, choose **File → Add Packages** and enter:

```
https://github.com/frontegg/frontegg-ios-swift
```

Or declare it in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/frontegg/frontegg-ios-swift.git", from: "1.3.19")
]
```

> Requires **iOS 14+** and **Swift 5.3+**. The [releases page](https://github.com/frontegg/frontegg-ios-swift/releases) has the current version.

## Quick start

**1 · Allow the redirect URLs.** In the Frontegg Portal, under **[ENVIRONMENT] → Authentication →
Login method**, turn hosted login on and add:

```
{{IOS_BUNDLE_IDENTIFIER}}://{{FRONTEGG_BASE_URL}}/ios/oauth/callback
{{FRONTEGG_BASE_URL}}/oauth/authorize
```

**2 · Add `Frontegg.plist`** to your project root. Your domain and client ID are in the Portal under
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

**3 · Wrap your root view.**

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

**4 · Read the authentication state** anywhere below it.

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

That is a working login. Building with UIKit instead? The
[Get Started guide](https://ios-swift-guide.frontegg.com/#/getting-started) covers it.

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

Questions, or something broken? Reach the team at
[support.frontegg.com](https://support.frontegg.com/frontegg/directories) or
[open an issue](https://github.com/frontegg/frontegg-ios-swift/issues).

Licensed under the [MIT License](https://github.com/frontegg/frontegg-ios-swift/blob/master/LICENSE).
