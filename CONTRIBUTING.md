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

The `Unit Tests (Thread Sanitizer)` job is configured with `continue-on-error: true`, `timeout-minutes: 15`, and `TSAN_OPTIONS=halt_on_error=1:abort_on_error=1`. It runs on every PR and reports findings; the test process aborts cleanly on the first race so the job completes in ~5 minutes regardless of whether races are found.

Findings do **not** block merge while the known race below is open:

**Race: `FronteggSwift.FronteggAuth.featureFlags` getter/setter contention across test setUps.**

```
Write of size 8 by main thread:
  FronteggAuth.featureFlags.setter ← FronteggAuth.manualInit ← FronteggApp.manualInit
  ← <NewTest>.setUp()

Previous read of size 8 by thread T19 (GCD worker):
  FronteggAuth.featureFlags.getter ← FronteggAuth.startPostConnectivityServices() async
  ← scheduled by <PriorTest>.setUp() via FronteggApp.shared.init()
```

A previous test's `FronteggApp.shared` init kicks off `startPostConnectivityServices()` on a GCD worker. That async task reads `FronteggAuth.featureFlags` while the next test's `setUp()` triggers `manualInit`, which writes `featureFlags`. The race window is real in production too — region switches in [FronteggAuth+RegionManagement.swift](Sources/FronteggSwift/auth/FronteggAuth+RegionManagement.swift) reassign `featureFlags` while async consumers may be reading it.

**Fix in a follow-up PR:** Either serialize `featureFlags` access through a serial queue / lock, or cancel in-flight `startPostConnectivityServices` tasks when `featureFlags` is reassigned (and on `FronteggAuth.resetForTesting`). The unit tests should also cancel/await any in-flight startup tasks in `tearDownWithError` so test isolation matches the production lifetime.

Once that race is closed, drop `continue-on-error: true` and promote TSan to a required check.

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
