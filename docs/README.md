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
- A [Hosted](https://github.com/frontegg/frontegg-ios-swift/tree/master/demo), [Embedded](https://github.com/frontegg/frontegg-ios-swift/tree/master/demo-embedded), [Application-Id](https://github.com/frontegg/frontegg-ios-swift/tree/master/demo-application-id), and [Multi-Region](https://github.com/frontegg/frontegg-ios-swift/tree/master/demo-multi-region) example projects to help you get started quickly

For full documentation, visit the Frontegg Developer Portal:  
🔗 [https://developers.frontegg.com](https://developers.frontegg.com)

---

## 🧑‍💻 Getting Started with Frontegg

Don't have a Frontegg account yet?  
Sign up here → [https://portal.us.frontegg.com/signup](https://portal.us.frontegg.com/signup)

---

## 📝 Logging

The SDK includes built-in logging capabilities to help you debug and monitor your application.

### Log Levels

The SDK supports the following log levels (from most verbose to least):

- `trace` - Detailed tracing information
- `debug` - Debug information for development
- `info` - General informational messages
- `warn` - Warning messages (default)
- `error` - Error conditions
- `critical` - Critical error conditions

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

### Example

To enable debug logging for troubleshooting:

1. Open your `Frontegg.plist` file
2. Add or update the `logLevel` key:
   ```xml
   <key>logLevel</key>
   <string>debug</string>
   ```
3. Optionally, enable trace ID logging:
   ```xml
   <key>enableTraceIdLogging</key>
   <true/>
   ```
4. Rebuild and run your application

---

## 💬 Support

Need help? Our team is here for you:  
[https://support.frontegg.com/frontegg/directories](https://support.frontegg.com/frontegg/directories)
