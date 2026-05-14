# Regression coverage and bug-class prevention for PRs #257, #258, #259

Date: 2026-05-14
Status: Approved — ready for implementation plan
Tracking: PRs [#257](https://github.com/frontegg/frontegg-ios-swift/pull/257), [#258](https://github.com/frontegg/frontegg-ios-swift/pull/258), [#259](https://github.com/frontegg/frontegg-ios-swift/pull/259)

## Background

Three production bug fixes recently landed on master:

- **FR-24808 (PR #257)** — Mis-routed OAuth callbacks in multi-app AASA setups, plus an `ASWebAuthenticationSessionError.canceledLogin` race that could mask a successful token exchange.
- **FR-24822 (PR #258)** — `CheckedContinuation` double-resume crash (`EXC_BREAKPOINT`) caused by `NWPathMonitor.pathUpdateHandler` re-entrancy in `NetworkStatusMonitor.routeIsAvailableOnce()`.
- **FR-24598 (PR #259)** — Embedded social-login watchdog reloading `/oauth/account/social/success`, causing the authorization code to be re-consumed and a generic error toast.

Each PR shipped its own unit tests. PR #257 also shipped an e2e test. CI already runs unit + e2e on every PR. The remaining gaps fall into two categories: *regression coverage for the specific bug behaviors* and *bug-class prevention for the future*.

## Goals

- Each of the three bugs has a regression test traceable to its FR ticket.
- The two bug *classes* surfaced here — concurrency races on `CheckedContinuation`/serial queues, and watchdog-driven WebView reloads — are surfaced automatically going forward.
- Reviewers can see per-file coverage moves on PRs without a hard threshold that forces churn.

## Non-goals

- Changing branch-protection rules from code (the user has admin access and will flip the switches; this spec only documents which checks should be required).
- Backfilling coverage on legacy code.
- Any change to production behavior.

## Scope

One PR. Six files touched:

```
.github/workflows/demo-e2e.yml
Tests/FronteggSwiftTests/CustomWebViewTests.swift
Tests/FronteggSwiftTests/FronteggAuthOAuthCallbackTests.swift
Tests/FronteggSwiftTests/NetworkStatusMonitorTests.swift
demo-embedded/demo-embedded-e2e/DemoEmbeddedE2ETests.swift
demo-embedded/demo-embedded-e2e/scenario-catalog.json
CONTRIBUTING.md   (new file)
```

Commits ordered: tags → e2e test → TSan job → coverage summary → CONTRIBUTING. Each piece is independently revertable.

---

## A1 — E2E pin for the social-success no-reload contract

PR #259 refactored the watchdog into a pure `SocialSuccessWatchdogAction` whose contract is "never reload `/oauth/account/social/success`". The unit test in [CustomWebViewTests.swift](../../../Tests/FronteggSwiftTests/CustomWebViewTests.swift) pins that contract on the pure logic. Nothing currently pins the integration — a future re-wire that bypasses the action would not fail any test.

### Design

New scenario in [DemoEmbeddedE2ETests.swift](../../../demo-embedded/demo-embedded-e2e/DemoEmbeddedE2ETests.swift): `testEmbeddedGoogleSocialSuccessWatchdogDoesNotReloadSuccessPage`.

Mirrors `testEmbeddedGoogleSocialLoginWithSystemWebAuthenticationSession` for setup, then:

1. Drive embedded Google social flow to `/oauth/account/social/success`.
2. Use `Self.server.waitForRequestCount(path: "/oauth/account/social/success", count: 1, timeout: 20)` to confirm the real success-page hit landed.
3. Sleep 6 seconds — past the 5-second `socialSuccessWatchdogDelay` in [CustomWebView.swift:29](../../../Sources/FronteggSwift/embedded/CustomWebView.swift:29).
4. Assert `Self.server.requestCount(path: "/oauth/account/social/success") == 1` — the watchdog must not have caused a reload.
5. Assert the authenticated screen is visible.

### Scenario catalog entry

Add to [scenario-catalog.json](../../../demo-embedded/demo-embedded-e2e/scenario-catalog.json):

```json
{
  "method": "testEmbeddedGoogleSocialSuccessWatchdogDoesNotReloadSuccessPage",
  "title": "Embedded Google social-success watchdog does not reload the success page",
  "description": "Drives the embedded Google social flow through to /oauth/account/social/success, waits past the watchdog delay, and verifies the watchdog never reloads the success page (which would re-consume the authorization code) and the user remains authenticated."
}
```

### Trade-off

The 6-second sleep is wall-clock cost on one test. Alternative — adding a debug seam to shorten `socialSuccessWatchdogDelay` from e2e — is more invasive than the cost it saves. Test stays self-contained.

---

## A2 — Regression-tag convention

### Format

```swift
// Regression: FR-NNNNN — <one-line summary>
```

For test-file section markers:

```swift
// MARK: - FR-NNNNN <Bug-class name> Regression Tests
```

### Application

- **FR-24808** — Tag `testMisroutedOpenURLRecoversIntoAuthenticatedState` in [DemoEmbeddedE2ETests.swift](../../../demo-embedded/demo-embedded-e2e/DemoEmbeddedE2ETests.swift) and the mis-routed-callback section in [FronteggAuthOAuthCallbackTests.swift](../../../Tests/FronteggSwiftTests/FronteggAuthOAuthCallbackTests.swift).
- **FR-24822** — Tag the new tests for `awaitFirstBoolResult` / `routeIsAvailableOnce` in [NetworkStatusMonitorTests.swift](../../../Tests/FronteggSwiftTests/NetworkStatusMonitorTests.swift).
- **FR-24598** — Tag the no-reload tests in [CustomWebViewTests.swift](../../../Tests/FronteggSwiftTests/CustomWebViewTests.swift) plus the new A1 e2e test.

The convention is documented in `CONTRIBUTING.md` (C1) so future regression tests follow it.

---

## B1 — Thread Sanitizer unit-test job

### Rationale

PR #258's bug was a `CheckedContinuation` double-resume — a continuation race exactly the kind of bug TSan is designed to catch. The unit test added in that PR catches the known case; TSan would surface future regressions of this *class*.

### Design

Add a new job to [demo-e2e.yml](../../../.github/workflows/demo-e2e.yml), parallel to the existing `unit-tests` job:

```yaml
unit-tests-tsan:
  name: "Unit Tests (Thread Sanitizer)"
  runs-on: "macos-15-xlarge"
  steps:
    - name: Checkout
      uses: actions/checkout@v6
    - name: Reset SwiftPM artifact cache
      run: bash .github/scripts/reset_swiftpm_artifact_cache.sh
    - name: Run Unit Tests with Thread Sanitizer
      run: |
        set -o pipefail
        xcodebuild test \
          -scheme FronteggSwift \
          -destination "platform=iOS Simulator,name=iPhone 16" \
          -only-testing:FronteggSwiftTests \
          -resultBundlePath "$RUNNER_TEMP/unit-tests-tsan.xcresult" \
          -enableThreadSanitizer YES \
          -enableCodeCoverage NO \
          -parallel-testing-enabled NO \
          2>&1 | tee "$RUNNER_TEMP/unit-tests-tsan.log"
    - name: Upload TSan artifacts
      uses: actions/upload-artifact@v7
      if: always()
      with:
        name: unit-tests-tsan-results
        path: |
          ${{ runner.temp }}/unit-tests-tsan.log
          ${{ runner.temp }}/unit-tests-tsan.xcresult
        retention-days: 7
```

`unit-tests-tsan` is added to the `summary` job's `needs:` list and rolled into the combined summary.

### Why a separate job

`-enableThreadSanitizer YES` is mutually exclusive with code coverage. The existing `unit-tests` job uses coverage; keeping them parallel preserves both signals at the cost of one extra job in the matrix.

### Gating

**Starts as a required check.** The suite is ~47 unit-test files on a serial runner; race reports should be deterministic, not flaky. If real-world flakiness emerges, follow-up will drop this job to advisory or pin specific suppressions — but flake-driven downgrade is not assumed up front.

### Risk: TSan false positives on first run

Mitigation: run the new TSan job locally before opening the PR. If anything pops in unrelated code, that's a separate fix; the options at that point are to (a) suppress narrowly via a sanitizer-suppressions file, (b) refactor the offending code, or (c) downgrade this job to advisory. None of those are blocked by this spec.

---

## B2 — Coverage informational PR comment

### Design

Add a step to the existing `summary` job in [demo-e2e.yml](../../../.github/workflows/demo-e2e.yml):

1. Extract coverage from the existing `unit-tests.xcresult` bundle:
   ```bash
   xcrun xccov view --report --files-for-target FronteggSwift --json \
     "$RUNNER_TEMP/artifacts/unit-tests-results/unit-tests.xcresult" \
     > "$RUNNER_TEMP/coverage.json"
   ```
2. Compute changed Swift files in the PR:
   ```bash
   git fetch --depth=1 origin master
   git diff --name-only origin/master...HEAD | grep '^Sources/FronteggSwift/.*\.swift$' \
     > "$RUNNER_TEMP/changed-files.txt"
   ```
3. Build a markdown table — one row per changed file with line-coverage % and covered/total lines.
4. Post as a sticky PR comment using `gh pr comment`. The comment includes the marker `<!-- coverage-summary -->` and the workflow uses `gh api ... pulls/{pr}/comments` to find and `gh pr comment --edit-last` (or equivalent) to update rather than stack.
5. Also append the table to `$GITHUB_STEP_SUMMARY` so the data is visible on the workflow run.

### Failure-safe

If `xccov` returns unexpected JSON (Apple has changed the shape across Xcode versions), the step logs a warning and exits 0. No PR comment is posted; CI does not break.

### Informational only

No threshold, no master-baseline comparison. The goal is visibility for reviewers, not a gate. A hard coverage gate would have been the original B2; we explicitly chose the informational path because the recent bugs were about *missing scenarios*, not low coverage.

---

## C1 — `CONTRIBUTING.md`

New file at repo root, with three sections:

### Running tests locally

Cribbed from [demo-e2e.yml](../../../.github/workflows/demo-e2e.yml):

```bash
# Unit tests
xcodebuild test \
  -scheme FronteggSwift \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:FronteggSwiftTests

# Unit tests with Thread Sanitizer (same as CI's unit-tests-tsan job)
xcodebuild test \
  -scheme FronteggSwift \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:FronteggSwiftTests \
  -enableThreadSanitizer YES \
  -enableCodeCoverage NO

# Embedded demo e2e tests
xcodebuild test \
  -project demo-embedded/demo-embedded.xcodeproj \
  -scheme demo-embedded \
  -destination "platform=iOS Simulator,name=iPhone 16 Pro" \
  -only-testing:demo-embedded-e2e
```

### Regression-test convention

Documents the A2 convention with two examples (a single-test tag and a `MARK:` section header).

### Required status checks (for maintainers)

Lists the checks that should be marked required in Settings → Branches → master → branch protection:

- `Validate PR Description`
- `Build & Lint`
- `Unit Tests`
- `Unit Tests (Thread Sanitizer)`
- Each `<app> (shard <i>/<n>)` matrix job from Demo E2E Tests
- `Swift SDK E2E` (as the existing [swift-sdk-e2e.yml:6](../../../.github/workflows/swift-sdk-e2e.yml:6) header already notes)

The user with admin access flips the switches; this section captures the intent so a future maintainer knows what should be required and why.

---

## PR structure

Single PR. Suggested commit order:

1. `test: tag regression tests with FR-24808 / FR-24822 / FR-24598`
2. `test: add e2e regression for social-success watchdog no-reload contract (FR-24598)`
3. `ci: add Thread Sanitizer unit-test job`
4. `ci: post per-file coverage summary on PRs`
5. `docs: add CONTRIBUTING.md with test, convention, and required-check guidance`

Each commit independently revertable.

## Open considerations

- Whether the existing `unit-tests` job's `iPhone 16` simulator destination matches what TSan job should use. The TSan job uses the same destination for parity; if simulator availability differs on `macos-15-xlarge`, adjust.
- Whether `gh pr comment --edit-last` is the right primitive for the sticky comment. Fallback: query existing comments via `gh api`, match the marker, then `gh api --method PATCH`. Decided during implementation; failure-safe path makes the choice low-risk.
