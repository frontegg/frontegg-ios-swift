# Contributing to frontegg-ios-swift

Thanks for sending a PR. This guide explains how to run the test suites locally and the conventions used to keep the suite traceable to production bugs.

## Running tests locally

The same commands that run in CI ([.github/workflows/demo-e2e.yml](.github/workflows/demo-e2e.yml)) can be run on any macOS host with Xcode 15+ installed.

### Unit tests

```bash
xcodebuild test \
  -scheme FronteggSwift \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:FronteggSwiftTests
```

### Unit tests with Thread Sanitizer

This is the same configuration as CI's `Unit Tests (Thread Sanitizer)` job. TSan and code coverage are mutually exclusive in xcodebuild, so coverage is disabled here:

```bash
xcodebuild test \
  -scheme FronteggSwift \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:FronteggSwiftTests \
  -enableThreadSanitizer YES \
  -enableCodeCoverage NO \
  -parallel-testing-enabled NO
```

Any output containing `ThreadSanitizer: data race` is a failure.

### Embedded demo end-to-end tests

```bash
xcodebuild test \
  -project demo-embedded/demo-embedded.xcodeproj \
  -scheme demo-embedded \
  -destination "platform=iOS Simulator,name=iPhone 16 Pro" \
  -only-testing:demo-embedded-e2e
```

E2E tests boot a `LocalMockAuthServer`, drive the embedded webview, and assert on real HTTP request counts. The mock-server source is at [demo-embedded/demo-embedded-e2e/LocalMockAuthServer.swift](demo-embedded/demo-embedded-e2e/LocalMockAuthServer.swift).

CI runs each matrix shard with `-retry-tests-on-failure -test-iterations 3` — a test that fails is automatically retried up to 3 times, but a test that passes runs exactly once. This absorbs single-iteration timing flakes without masking persistent regressions.

### Known CI-flaky tests

Some tests pass locally but flake on `macos-15-xlarge` runners due to environment timing (slow `ASWebAuthenticationSession` startup, simulator state pollution that retries can't reset at the system level). These are listed below and currently quarantined from CI via `-skip-testing` flags in [.github/workflows/demo-e2e.yml](.github/workflows/demo-e2e.yml). They still run for local development — fix and re-enable when their root cause is addressed.

| Test | Reason | Action item |
|---|---|---|
| `DemoEmbeddedE2ETests.testEmbeddedGoogleSocialLoginRecoversFromStalledSocialSuccessPage` | First iteration takes 60–70 s on slow CI runners; retries fail because `ASWebAuthenticationSession` system-level state leaks between iterations | Reset `WKWebsiteDataStore` / simulator browser state in `tearDownWithError`, or split this test into a separate non-retried job |

### Thread Sanitizer — currently advisory

The `Unit Tests (Thread Sanitizer)` job is configured with `continue-on-error: true` and `timeout-minutes: 15`. It runs on every PR, reports findings, and completes in ~7 minutes. Findings do **not** block merge while the two open races below are tracked for follow-up.

Drop `continue-on-error: true` and promote TSan to a required check once both open races are closed.

#### Past findings (resolved)

- **`FronteggAuth.featureFlags` data race** — concurrent main-thread reassignment (from `manualInit` and region-switch entry points in `FronteggAuth+RegionManagement.swift`) racing with background-thread reads in `startPostConnectivityServices()` and `SocialLoginUrlGenerator`. The race wedged xcodebuild for 25+ minutes on every PR, blocking the Combine Results & Summary step on unrelated PRs. Fixed by serializing access through an `NSLock`-backed computed property. Regression test: [`Tests/FronteggSwiftTests/FronteggAuthFeatureFlagsRaceTests.swift`](Tests/FronteggSwiftTests/FronteggAuthFeatureFlagsRaceTests.swift).

#### Open findings (follow-up PRs)

These surfaced once the `featureFlags` crash no longer aborted the suite first.

1. **`FronteggAuth.refreshTokenDispatch` getter/setter race** *(production code)*

   ```
   Write: FronteggAuth.cancelScheduledTokenRefresh ← FronteggAuth.scheduleTokenRefresh
        (async closure on GCD worker T1)
   Read:  FronteggAuth.hasScheduledTokenRefreshForTesting (from a test's async closure on T3)
   ```

   `refreshTokenDispatch: DispatchWorkItem?` is read/written across `scheduleTokenRefresh`, `cancelScheduledTokenRefresh`, and `hasScheduledTokenRefreshForTesting` without synchronization. Apply the same lock-backed computed-property pattern as `featureFlags`.

2. **`MockRefreshRecoveryApi.refreshToken` Swift access race** *(test-side)*

   The mock in `FronteggAuthRefreshRecoveryTests` mutates internal state (call counts, response queues) from concurrent async contexts without synchronization. Add an internal lock or convert the mock to an actor.

3. **`LoggerDelegateTests.setUp()` data race** *(test-side)*

   Concurrent access to delegate-registration state across `LoggerDelegateTests` instances. Same fix shape as #2 — serialize the relevant state in the test or its harness.

#### Known follow-up — same pattern, no TSan finding yet

`FronteggAuth.api` and `FronteggAuth.entitlements` share the exact reassignment pattern that `featureFlags` had — reassigned in the same four sites in [`FronteggAuth+RegionManagement.swift`](Sources/FronteggSwift/auth/FronteggAuth+RegionManagement.swift) and read across multiple threads. TSan did not surface those races on the test ordering we ran, but the same fix pattern should be applied to both before they bite in production region-switch flows.

## Regression-test convention

Every test that exists *because* a specific production bug was found should be traceable to its Frontegg ticket. Use this convention.

### Single test

```swift
// Regression: FR-24598 — the social-success watchdog must never reload
// /oauth/account/social/success, because reloading re-consumes the
// authorization code and surfaces a generic OAuth error.
func test_socialSuccessWatchdog_doesNotReload() {
    // ...
}
```

### Section of tests

When several tests cluster around the same bug, use a `MARK` section:

```swift
// MARK: - FR-24822 One-shot CheckedContinuation safety (issue #256)
// Regression: FR-24822 — NWPathMonitor.pathUpdateHandler can re-enter
// and resume a CheckedContinuation twice, crashing with EXC_BREAKPOINT.
```

Use the FR-NNNNN form (matching the Frontegg ticket ID). If a related public issue exists (`issue #256` etc.), include it after the FR tag for cross-reference.

## Required status checks (for maintainers)

The following checks should be marked **required** in Settings → Branches → master → branch protection. The intent is that no PR can merge if any of these are failing.

| Check name | Source workflow | Why required |
|---|---|---|
| `Validate PR Description` | [onPullRequestUpdated.yaml](.github/workflows/onPullRequestUpdated.yaml) | CHANGELOG generation needs a non-empty description |
| `Build & Lint` | [onPullRequestUpdated.yaml](.github/workflows/onPullRequestUpdated.yaml) | SwiftPM resolves + SDK builds for iPhone 16 simulator |
| `Unit Tests` | [demo-e2e.yml](.github/workflows/demo-e2e.yml) | `FronteggSwiftTests` with coverage |
| `embedded (shard 1/N)` (and other matrix shards) | [demo-e2e.yml](.github/workflows/demo-e2e.yml) | Embedded e2e — covers social/SAML/OIDC flows, deep-link recovery, offline mode |
| `multi-region (shard …)`, `uikit (shard …)`, `auto-login (shard …)` | [demo-e2e.yml](.github/workflows/demo-e2e.yml) | Per-variant e2e |
| `Swift SDK E2E` | [swift-sdk-e2e.yml](.github/workflows/swift-sdk-e2e.yml) | External system-tests suite (only for non-master target branches) |

The `Demo E2E Tests` workflow uses a generated matrix, so the exact shard names depend on the `shard_count` input. Adding `embedded`, `multi-region`, `uikit`, and `auto-login` to the required-checks list at the top level covers them once shard 1 reports.
