# FronteggAuth.featureFlags race fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the data race on `FronteggAuth.featureFlags` so the TSan CI job stops hanging and other PRs stop getting blocked by the failing Combine Results & Summary step.

**Architecture:** Convert `public var featureFlags: FeatureFlags` from a stored property to a computed property backed by a private storage var (`_featureFlags`) guarded by an `NSLock`. Every read and write of `featureFlags` from anywhere in the codebase (including extensions and call sites) routes through the lock-protected accessor. Zero public API change.

**Tech Stack:** Swift 5.5+, `NSLock` with the existing `withLock { }` extension at [`Sources/FronteggSwift/utils/NetworkStatusMonitor.swift:13`](../../../Sources/FronteggSwift/utils/NetworkStatusMonitor.swift:13). XCTest with `-enableThreadSanitizer YES` for verification.

**Spec:** [docs/superpowers/specs/2026-05-18-featureflags-race-fix-design.md](../specs/2026-05-18-featureflags-race-fix-design.md)

---

## Task 1: Add red regression test

This task proves the race exists. Test should FAIL under TSan on master/this-branch's current state. Don't proceed to Task 2 until you've seen the red.

**Files:**
- Create: `Tests/FronteggSwiftTests/FronteggAuthFeatureFlagsRaceTests.swift`

- [ ] **Step 1: Create the test file with concurrent read+write**

Write this file:

```swift
//
//  FronteggAuthFeatureFlagsRaceTests.swift
//  FronteggSwiftTests
//
//  Regression test for the FronteggAuth.featureFlags data race that hung the
//  TSan CI job for 15+ minutes on every PR. The race occurs when the next
//  test's setUp() calls FronteggApp.shared.manualInit() (which reassigns
//  featureFlags on the main thread) while a prior test's
//  startPostConnectivityServices() is still reading featureFlags on a GCD
//  worker. This test forces the race directly and asserts it does not occur
//  when -enableThreadSanitizer YES is set.
//

import XCTest
@testable import FronteggSwift

final class FronteggAuthFeatureFlagsRaceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        PlistHelper.testConfigOverride = FronteggPlist(
            lateInit: true,
            payload: .singleRegion(
                .init(baseUrl: "https://test.frontegg.com", clientId: "test-client")
            ),
            keepUserLoggedInAfterReinstall: false
        )
        FronteggApp.shared.manualInit(
            baseUrl: "https://test.frontegg.com",
            cliendId: "test-client",
            applicationId: nil
        )
    }

    override func tearDown() {
        PlistHelper.testConfigOverride = nil
        super.tearDown()
    }

    func test_featureFlags_concurrentReassignmentAndRead_doesNotRace() async {
        // Direct repro: write on the main thread while reading from a
        // background thread, the same shape as manualInit (writer) vs
        // startPostConnectivityServices (reader) in production.
        let auth = FronteggAuth.shared
        let iterations = 10_000

        async let writer: Void = Task.detached {
            for _ in 0..<iterations {
                auth.featureFlags = FeatureFlags(
                    .init(clientId: "test-client", api: auth.api)
                )
            }
        }.value

        async let reader: Void = Task.detached {
            for _ in 0..<iterations {
                _ = auth.featureFlags
            }
        }.value

        _ = await (writer, reader)

        // The functional assertion: after all the churn, featureFlags is
        // still readable and yields a non-torn reference.
        XCTAssertNotNil(auth.featureFlags)
    }
}
```

- [ ] **Step 2: Build the test target to verify it compiles**

Run:
```bash
xcodebuild build-for-testing \
  -scheme FronteggSwift \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:FronteggSwiftTests/FronteggAuthFeatureFlagsRaceTests 2>&1 | tail -5
```
Expected: `** TEST BUILD SUCCEEDED **`. If you get a compile error about `PlistHelper.testConfigOverride` or `FronteggPlist`, copy the exact `setUp` from [`Tests/FronteggSwiftTests/AuthorizeUrlGeneratorTests.swift:15-31`](../../../Tests/FronteggSwiftTests/AuthorizeUrlGeneratorTests.swift) — that's the established pattern.

- [ ] **Step 3: Run under TSan to see the RED**

Run:
```bash
xcodebuild test \
  -scheme FronteggSwift \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:FronteggSwiftTests/FronteggAuthFeatureFlagsRaceTests \
  -enableThreadSanitizer YES \
  -enableCodeCoverage NO \
  -parallel-testing-enabled NO 2>&1 | tee /tmp/race-red.log | grep -E "ThreadSanitizer|Test Case.*(passed|failed)|TEST" | head -10
```
Expected: at least one `WARNING: ThreadSanitizer: data race` line referencing `FronteggSwift.FronteggAuth.featureFlags.setter` or `.getter`. The xctest binary may abort (this is the bug we're fixing) — that's fine, the WARNING line in `/tmp/race-red.log` is the proof.

If you do NOT see `WARNING: ThreadSanitizer`, the race didn't reproduce in this run. Increase `iterations` to 100_000 and try again. The race must be observed before proceeding.

- [ ] **Step 4: Commit the red test alone**

```bash
git add Tests/FronteggSwiftTests/FronteggAuthFeatureFlagsRaceTests.swift
git commit -m "$(cat <<'EOF'
test: add red regression test for FronteggAuth.featureFlags race

Forces the same write-vs-read pattern that TSan detected in CI
(manualInit reassigning featureFlags on main thread while
startPostConnectivityServices reads it on a GCD worker). Under
-enableThreadSanitizer YES this test reports a data race today;
the next commit fixes that.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

The commit-before-fix gives a clean RED commit that future engineers can `git checkout <SHA>` to reproduce the bug.

---

## Task 2: Apply the lock fix

This task turns the test from RED to GREEN.

**Files:**
- Modify: `Sources/FronteggSwift/FronteggAuth.swift` (line 56 — the property declaration; line 127 — the init assignment)

- [ ] **Step 1: Convert `featureFlags` to a lock-backed computed property**

In [`Sources/FronteggSwift/FronteggAuth.swift`](../../../Sources/FronteggSwift/FronteggAuth.swift), replace this single line (currently line 56):

```swift
    public var featureFlags: FeatureFlags
```

with these eight lines:

```swift
    // Lock-protected storage for the public `featureFlags` accessor below.
    // FronteggAuth.featureFlags is reassigned during region switches and on
    // every test's setUp via manualInit, while async work from a prior
    // setUp's startPostConnectivityServices() may still be reading it on a
    // GCD worker. Serialize all access to avoid the data race.
    private let featureFlagsLock = NSLock()
    private var _featureFlags: FeatureFlags
    public var featureFlags: FeatureFlags {
        get { featureFlagsLock.withLock { _featureFlags } }
        set { featureFlagsLock.withLock { _featureFlags = newValue } }
    }
```

- [ ] **Step 2: Update the init assignment to use the private storage**

The init at [`Sources/FronteggSwift/FronteggAuth.swift:127`](../../../Sources/FronteggSwift/FronteggAuth.swift:127) currently reads:

```swift
        self.featureFlags = FeatureFlags(.init(clientId: self.clientId, api: self.api))
```

Replace with:

```swift
        self._featureFlags = FeatureFlags(.init(clientId: self.clientId, api: self.api))
```

This is the only place in the codebase that needs to use `_featureFlags` directly — `_featureFlags` is non-optional, so init must initialize it directly (the setter would read `_featureFlags` before it's been initialized, which is undefined in Swift). Every other reassignment goes through the public `featureFlags` setter (and therefore the lock).

- [ ] **Step 3: Build to verify compilation**

```bash
xcodebuild build-for-testing \
  -scheme FronteggSwift \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:FronteggSwiftTests 2>&1 | tail -5
```
Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 4: Run the race test under TSan to see GREEN**

```bash
xcodebuild test \
  -scheme FronteggSwift \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:FronteggSwiftTests/FronteggAuthFeatureFlagsRaceTests \
  -enableThreadSanitizer YES \
  -enableCodeCoverage NO \
  -parallel-testing-enabled NO 2>&1 | tee /tmp/race-green.log | grep -E "ThreadSanitizer|Test Case.*(passed|failed)|TEST" | head -10
```
Expected:
- `Test Case '-[FronteggSwiftTests.FronteggAuthFeatureFlagsRaceTests test_featureFlags_concurrentReassignmentAndRead_doesNotRace]' passed`
- NO `WARNING: ThreadSanitizer` lines in `/tmp/race-green.log`
- `** TEST SUCCEEDED **`

If TSan still reports a race, the lock is being applied somewhere it shouldn't be. Re-read your edits — particularly that `_featureFlags` is `private` and not accessed anywhere outside the accessor + init.

- [ ] **Step 5: Run the FULL unit-test suite under TSan to confirm no other races surface**

```bash
xcodebuild test \
  -scheme FronteggSwift \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:FronteggSwiftTests \
  -enableThreadSanitizer YES \
  -enableCodeCoverage NO \
  -parallel-testing-enabled NO 2>&1 | tee /tmp/full-suite-tsan.log | tail -20
```
Expected:
- `** TEST SUCCEEDED **`
- Total time well under 15 min (more like 5–8 min)
- `grep -c "WARNING: ThreadSanitizer" /tmp/full-suite-tsan.log` returns `0`

If a different race surfaces here that's not on `featureFlags`, STOP and report. Don't try to fix it in this PR — that's separate scope per the spec's non-goals.

- [ ] **Step 6: Commit the fix**

```bash
git add Sources/FronteggSwift/FronteggAuth.swift
git commit -m "$(cat <<'EOF'
fix(FronteggAuth): serialize featureFlags reads/writes via NSLock

The previous `public var featureFlags: FeatureFlags` stored property
allowed concurrent main-thread reassignment (from manualInit and the
4 region-switch entry points in FronteggAuth+RegionManagement.swift)
to race with background-thread reads in startPostConnectivityServices()
and SocialLoginUrlGenerator. TSan reported this race in CI; the resulting
abort wedged xcodebuild for 25+ minutes on every PR.

Convert featureFlags to a computed property backed by a private
_featureFlags storage var guarded by an NSLock. Every existing call
site reads/writes through the public property unchanged — locking is
transparent.

Init writes _featureFlags directly because the property must be
initialized before the setter (which reads _featureFlags) is safe.
This is the only place that touches _featureFlags directly.

The new FronteggAuthFeatureFlagsRaceTests regression test goes from
RED to GREEN with this commit.

The `api` and `entitlements` properties share the same reassignment
pattern in FronteggAuth+RegionManagement.swift — they are flagged for
a follow-up PR in CONTRIBUTING.md but not addressed here.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Promote TSan to a required check

Now that the race is fixed, drop the workarounds that made the TSan job advisory.

**Files:**
- Modify: `.github/workflows/demo-e2e.yml` (the `unit-tests-tsan:` job block, currently around lines 55–95)

- [ ] **Step 1: Drop `continue-on-error`, tighten timeout, drop TSAN_OPTIONS, drop tolerance line**

In [`.github/workflows/demo-e2e.yml`](../../../.github/workflows/demo-e2e.yml), find the `unit-tests-tsan:` job. Replace the entire job block with:

```yaml
  unit-tests-tsan:
    name: "Unit Tests (Thread Sanitizer)"
    runs-on: "macos-15-xlarge"
    timeout-minutes: 15
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

Compared to the previous version, this removes:
- `continue-on-error: true` — TSan findings now fail the PR
- The `env: TSAN_OPTIONS: ...` block — abort-on-error is irrelevant when no race fires
- The `|| echo "xcodebuild exited non-zero ..."` tolerance line — non-zero exit is now a real failure
- The multi-line "Advisory:" comment above `timeout-minutes` — no longer advisory

The job stays at `timeout-minutes: 15` (a comfortable safety net — the suite should complete in well under 10 minutes).

- [ ] **Step 2: Validate YAML**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/demo-e2e.yml')); print('YAML OK')"
```
Expected: `YAML OK`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/demo-e2e.yml
git commit -m "$(cat <<'EOF'
ci(tsan): promote Thread Sanitizer to a required check

The FronteggAuth.featureFlags race that caused the 25-min hang is
fixed in the previous commit. With no race left to detect, the workarounds
that made this job advisory are no longer needed:

- Drop `continue-on-error: true` — TSan findings now fail the PR.
- Drop `TSAN_OPTIONS=halt_on_error=1:abort_on_error=1` — abort behavior
  is irrelevant when no race fires.
- Drop the `|| echo "..."` tolerance after xcodebuild — a non-zero exit
  is now a genuine signal.

Job timeout stays at 15 minutes as a safety net; the suite is expected
to complete in well under 10 minutes.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Update CONTRIBUTING.md

Move the now-fixed race from "Known TSan findings" to a "Past findings" entry, and flag the related-but-still-open `api`/`entitlements` reassignment pattern.

**Files:**
- Modify: `CONTRIBUTING.md` (the "Thread Sanitizer — currently advisory" section)

- [ ] **Step 1: Replace the "Thread Sanitizer — currently advisory" section**

Find the section that starts with `### Thread Sanitizer — currently advisory` in [`CONTRIBUTING.md`](../../../CONTRIBUTING.md). Replace it (from that heading down through the entire fenced code block plus the paragraphs describing the race and the fix instructions, up to but not including the next `## ` heading — which should be `## Regression-test convention`) with:

```markdown
### Thread Sanitizer

The `Unit Tests (Thread Sanitizer)` job is a required check on every PR. It runs `FronteggSwiftTests` with `-enableThreadSanitizer YES`; any TSan finding fails the PR.

Job timeout: 15 minutes (typical run is under 10).

#### Past findings (resolved)

- **`FronteggAuth.featureFlags` data race** — concurrent main-thread reassignment (from `manualInit` and region-switch entry points) racing with background-thread reads in `startPostConnectivityServices()` and `SocialLoginUrlGenerator`. Fixed in PR [#264](https://github.com/frontegg/frontegg-ios-swift/pull/264) by serializing reads/writes through an `NSLock`. The regression is pinned by `FronteggAuthFeatureFlagsRaceTests`.

#### Known follow-up

`FronteggAuth.api` and `FronteggAuth.entitlements` share the exact reassignment pattern as `featureFlags` did — they are reassigned in the same four sites in [`FronteggAuth+RegionManagement.swift`](Sources/FronteggSwift/auth/FronteggAuth+RegionManagement.swift) and read across multiple threads. TSan did not surface those races on the test ordering we ran, but the same fix pattern (lock-backed computed property) should be applied to both as a follow-up PR before they bite in production region-switch flows.
```

- [ ] **Step 2: Verify markdown structure**

```bash
test -f CONTRIBUTING.md && \
  grep -c "### Thread Sanitizer" CONTRIBUTING.md && \
  grep -c "currently advisory" CONTRIBUTING.md
```
Expected:
- First `grep -c` returns `1` (one section header now)
- Second `grep -c` returns `0` (no more "currently advisory" wording)

- [ ] **Step 3: Commit**

```bash
git add CONTRIBUTING.md
git commit -m "$(cat <<'EOF'
docs: move FronteggAuth.featureFlags race to "Past findings"

The race is fixed in this PR; documentation now reflects that the TSan
job is required (not advisory) and the FeatureFlags race is resolved.

Adds a "Known follow-up" pointer for the same reassignment pattern on
FronteggAuth.api and FronteggAuth.entitlements, which will need the
same lock-backed treatment in a subsequent PR.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Push and verify CI

- [ ] **Step 1: Verify commit ordering**

```bash
git log --oneline origin/master..HEAD
```
Expected (newest first):

1. `docs: move FronteggAuth.featureFlags race to "Past findings"`
2. `ci(tsan): promote Thread Sanitizer to a required check`
3. `fix(FronteggAuth): serialize featureFlags reads/writes via NSLock`
4. `test: add red regression test for FronteggAuth.featureFlags race`
5. `docs: add spec for FronteggAuth.featureFlags race fix` (from earlier in the brainstorm)
6. (prior commits from PR #264)

If the order is different, rebase interactively to match. The test→fix split must be preserved so the RED commit is bisectable.

- [ ] **Step 2: Push to PR #264**

```bash
git push origin remove-tsan-ci-job 2>&1 | tail -3
```

- [ ] **Step 3: Watch the TSan job**

```bash
gh pr checks 264 --required=false 2>&1 | grep -E "Thread Sanitizer|Combine"
```

Expected after ~5–10 minutes:
- `Unit Tests (Thread Sanitizer)  pass  X m Y s` (well under 15 min, no `continue-on-error` because it's a required check now)
- `Combine Results & Summary  pass  17s`

If `Unit Tests (Thread Sanitizer)` fails:
- `gh api repos/frontegg/frontegg-ios-swift/actions/jobs/<JOB_ID>/logs | grep -E "ThreadSanitizer|Test Case.*failed"` to see which test or race failed
- If a different race surfaces (e.g. on `api` or `entitlements`): roll the CI promotion back (revert Task 3's commit) so the PR can ship the FeatureFlags fix without being blocked by an unrelated finding, and open a follow-up issue.

- [ ] **Step 4: Confirm Combine Summary passes downstream**

```bash
gh pr checks 264 2>&1 | grep -E "fail" | head -5
```
Expected: no `fail` rows (or only pre-existing flakes unrelated to the TSan path).

---

## Self-review checklist (already run by author)

- ✅ **Spec coverage:**
  - "Lock-backed computed property" → Task 2 Step 1
  - "Init point" (`_featureFlags` direct init) → Task 2 Step 2
  - "Reassignment sites" (RegionManagement extensions unchanged) → no task needed; they go through the public setter
  - "Read sites" (no changes) → no task needed
  - "Testing — new regression test" → Task 1
  - "Local TSan verification" → Task 1 Step 3 (RED) + Task 2 Step 4 (GREEN)
  - "Full-suite TSan verification on CI" → Task 5 Step 3
  - PR commit structure (4 commits) → Tasks 1, 2, 3, 4 each end in a commit
- ✅ **Placeholder scan:** no TBD / TODO / "handle appropriately". Every code step includes the full code. Every command has the expected output.
- ✅ **Type consistency:** `_featureFlags` (private storage), `featureFlagsLock` (lock), `featureFlags` (public computed) — consistent across all tasks. `FronteggAuthFeatureFlagsRaceTests` class name + test method name match across Task 1 (creation) and Task 5 (CI lookup).
- ✅ **Bisectability:** the test commit (Task 1) lands BEFORE the fix commit (Task 2), so `git checkout <test-commit-SHA>` reproduces the bug for any future engineer who needs to verify.
