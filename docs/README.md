# Frontegg iOS SDK
![Frontegg_iOS_SDK (Swift)](/images/frontegg-swift.png)

Welcome to the official **Frontegg iOS SDK** — your all-in-one solution for
integrating authentication and user management into your iOS mobile
app. [Frontegg](https://frontegg.com/) is a self-served user management platform, built for modern
SaaS applications. Easily implement authentication, SSO, RBAC, multi-tenancy, and more — all from a
single SDK.

## 📚 Documentation

This repository includes:

- A [Get Started](https://ios-swift-guide.frontegg.com/#/getting-started) guide for quick integration
- A [Setup Guide](https://ios-swift-guide.frontegg.com/#/setup) with detailed setup instructions
- An [API Reference](https://ios-swift-guide.frontegg.com/#/api) for detailed SDK functionality
- [Usage Examples](https://ios-swift-guide.frontegg.com/#/usage) with common implementation patterns
- [Advanced Topics](https://ios-swift-guide.frontegg.com/#/advanced) for complex integration scenarios
- An [Offline Mode](https://ios-swift-guide.frontegg.com/#/offline-mode) guide for custom offline UI, reconnect behavior, and logout expectations
- A [Hosted](https://github.com/frontegg/frontegg-ios-swift/tree/master/demo), [Embedded](https://github.com/frontegg/frontegg-ios-swift/tree/master/demo-embedded), [Application-Id](https://github.com/frontegg/frontegg-ios-swift/tree/master/demo-application-id), and [Multi-Region](https://github.com/frontegg/frontegg-ios-swift/tree/master/demo-multi-region) example projects to help you get started quickly

For full documentation, visit the Frontegg Developer Portal:  
🔗 [https://developers.frontegg.com](https://developers.frontegg.com)

---

## Advanced

### Disable Auto Refresh

You can disable automatic token refresh by adding `disableAutoRefresh` to `Frontegg.plist`:

```xml
<key>disableAutoRefresh</key>
<true/>
```

Behavior:

- Default value is `false` (auto refresh is enabled).
- When `disableAutoRefresh` is `true`, SDK internal/automatic refresh flows are blocked(including offline mode refreshing, timers and etc.).
- Manual refresh calls (for example, `getOrRefreshAccessTokenAsync()`) still work.
- This lets apps fully control when token refresh happens while keeping explicit refresh APIs available.

### Entitlements

The SDK can load and check user entitlements (features and permissions) from the Frontegg Entitlements API. Enable entitlements in `Frontegg.plist` with `entitlementsEnabled: true`, then:

1. Entitlements are fetched automatically on login. You can also call `FronteggApp.shared.auth.loadEntitlements(forceRefresh:completion:)` yourself: by default (`forceRefresh: false`) the SDK uses cached entitlements when available (no network call). Pass `forceRefresh: true` to always fetch from the API (`GET .../frontegg/entitlements/api/v2/user-entitlements`).
2. Use the cached state for local checks:
   - `getFeatureEntitlements(featureKey:)` — check by feature key
   - `getPermissionEntitlements(permissionKey:)` — check by permission key
   - `getEntitlements(options:)` — unified check with `EntitledToOptions.featureKey(_)` or `.permissionKey(_)`

All checks after `loadEntitlements` use in-memory state only (no extra network calls). Cache is cleared on logout. Access the raw cached set of keys via `FronteggApp.shared.auth.entitlements.state` (`EntitlementState`: `featureKeys`, `permissionKeys`).

---

## 🧑‍💻 Getting Started with Frontegg

Don't have a Frontegg account yet?  
Sign up here → [https://portal.us.frontegg.com/signup](https://portal.us.frontegg.com/signup)

---

## 💬 Support

Need help? Our team is here for you:  
[https://support.frontegg.com/frontegg/directories](https://support.frontegg.com/frontegg/directories)
