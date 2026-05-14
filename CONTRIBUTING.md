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
| `Unit Tests (Thread Sanitizer)` | [demo-e2e.yml](.github/workflows/demo-e2e.yml) | Catches `CheckedContinuation` races and other concurrency bugs |
| `embedded (shard 1/N)` (and other matrix shards) | [demo-e2e.yml](.github/workflows/demo-e2e.yml) | Embedded e2e — covers social/SAML/OIDC flows, deep-link recovery, offline mode |
| `multi-region (shard …)`, `uikit (shard …)`, `auto-login (shard …)` | [demo-e2e.yml](.github/workflows/demo-e2e.yml) | Per-variant e2e |
| `Swift SDK E2E` | [swift-sdk-e2e.yml](.github/workflows/swift-sdk-e2e.yml) | External system-tests suite (only for non-master target branches) |

The `Demo E2E Tests` workflow uses a generated matrix, so the exact shard names depend on the `shard_count` input. Adding `embedded`, `multi-region`, `uikit`, and `auto-login` to the required-checks list at the top level covers them once shard 1 reports.
