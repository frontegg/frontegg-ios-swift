# Fix `FronteggAuth.featureFlags` data race

Date: 2026-05-18
Status: Approved — ready for implementation plan
Tracking: PR [#264](https://github.com/frontegg/frontegg-ios-swift/pull/264) (TSan job currently advisory because of this race)

## Background

Thread Sanitizer detected a real data race on `FronteggAuth.featureFlags`:

```
Write of size 8 by main thread:
  FronteggAuth.featureFlags.setter ← FronteggAuth.manualInit ← FronteggApp.manualInit
  ← <NewTest>.setUp()

Previous read of size 8 by thread T19 (GCD worker):
  FronteggAuth.featureFlags.getter ← FronteggAuth.startPostConnectivityServices() async
  ← scheduled by <PriorTest>.setUp() via FronteggApp.shared.init()
```

The race surfaces in two ways:

| Scenario | Where | Severity |
|---|---|---|
| Test isolation | Prior test's `startPostConnectivityServices()` still running on a GCD worker when next test's `setUp()` calls `manualInit` and reassigns `featureFlags`. | Test-only — causes the TSan CI job to hang at 15-min timeout, preventing artifact upload, which makes Combine Summary fail at 11s on every PR. |
| Production region switch | App reads `featureFlags` from `SocialLoginUrlGenerator` while a user-triggered `reinitWithRegion(...)` reassigns it on the main thread. | Real production race — rare (only during multi-region region switch) but real. |

## Goal

Serialize all reads and writes of `FronteggAuth.featureFlags` so a reader sees a consistent reference and a writer never overlaps a reader. Close both manifestations of the race in one PR.

## Non-goals

- Fixing the same race pattern on `api` and `entitlements` properties (they share the reassignment pattern in `FronteggAuth+RegionManagement.swift`). Pattern established here can be extended to those in a follow-up — adding them now would balloon the diff.
- Refactoring to `@MainActor` or actor-based concurrency. Codebase uses `NSLock` (`connectivityGenerationLock`, `logoutTransitionLock`, `entitlementsLoadLock`, etc.) — staying with the established pattern.
- Cancelling in-flight `startPostConnectivityServices` tasks on reassignment. The lock alone closes the race; cancellation is an optimisation we don't need.

## Design

### Lock-backed computed property

In [Sources/FronteggSwift/FronteggAuth.swift](../../../Sources/FronteggSwift/FronteggAuth.swift), replace the stored property:

```swift
public var featureFlags: FeatureFlags
```

with a lock-protected accessor pair around a private storage variable:

```swift
private let featureFlagsLock = NSLock()
private var _featureFlags: FeatureFlags

public var featureFlags: FeatureFlags {
    get { featureFlagsLock.withLock { _featureFlags } }
    set { featureFlagsLock.withLock { _featureFlags = newValue } }
}
```

The `NSLock.withLock` extension already exists at [Sources/FronteggSwift/utils/NetworkStatusMonitor.swift:13](../../../Sources/FronteggSwift/utils/NetworkStatusMonitor.swift:13). The public API is unchanged — every existing read and write site continues using `self.featureFlags` exactly as before, with the lock applied transparently.

### Init point

The single line in `FronteggAuth.init()` at line 127:

```swift
self.featureFlags = FeatureFlags(.init(clientId: self.clientId, api: self.api))
```

stays as-is. With the computed property, this routes through the setter under lock — safe even though `init` is single-threaded, and uniform with other write sites.

### Reassignment sites (extensions in `FronteggAuth+RegionManagement.swift`)

All four reassignment sites (lines 18, 35, 48, 62) continue using `self.featureFlags = FeatureFlags(...)`. Each write now acquires the lock; concurrent reads from `startPostConnectivityServices` wait their turn.

### Read sites

No changes needed. The existing read sites (`SocialLoginUrlGenerator.swift:297, 378`, `FronteggAuth+Connectivity.swift:20-21`, any others) read through the public property, which now locks.

## Files touched

| File | Change |
|---|---|
| `Sources/FronteggSwift/FronteggAuth.swift` | Add `featureFlagsLock` + `_featureFlags`; convert `public var featureFlags` to computed property with locked getter/setter. |
| `Tests/FronteggSwiftTests/FronteggAuthFeatureFlagsRaceTests.swift` *(new)* | Regression test that hammers concurrent read+write to `featureFlags`. RED before fix (TSan reports race), GREEN after fix (no race). |
| `.github/workflows/demo-e2e.yml` | After local TSan run confirms clean: drop `continue-on-error: true`, drop the `\|\| echo …` tolerance line, drop the now-redundant `TSAN_OPTIONS` (race shouldn't fire so abort behavior is irrelevant). Promote TSan to required. |
| `CONTRIBUTING.md` | Move the `FronteggAuth.featureFlags` race from "Known TSan findings (currently advisory)" to a "Past findings (resolved)" section. Note that `api` and `entitlements` share the reassignment pattern and are flagged as follow-up. |

## Testing

### New regression test

File: `Tests/FronteggSwiftTests/FronteggAuthFeatureFlagsRaceTests.swift`

Pattern:

```swift
final class FronteggAuthFeatureFlagsRaceTests: XCTestCase {
    func test_featureFlagsConcurrentReassignmentAndRead_doesNotRace() async {
        let auth = FronteggAuth.shared
        let iterations = 10_000

        async let writer: Void = {
            for _ in 0..<iterations {
                auth.featureFlags = FeatureFlags(.init(clientId: "test", api: auth.api))
            }
        }()

        async let reader: Void = {
            for _ in 0..<iterations {
                _ = auth.featureFlags
            }
        }()

        _ = await (writer, reader)
    }
}
```

### Local TSan verification (red-then-green)

1. Run on master (race present): `xcodebuild test -scheme FronteggSwift -enableThreadSanitizer YES -only-testing:FronteggSwiftTests/FronteggAuthFeatureFlagsRaceTests` → expect `WARNING: ThreadSanitizer: data race`.
2. Apply the lock fix.
3. Re-run same command → expect no TSan warnings, test passes.

### Full-suite TSan verification on CI

After pushing, the `Unit Tests (Thread Sanitizer)` job should:
- Complete in ~5–10 min (not hit the 15-min timeout)
- Report zero `WARNING: ThreadSanitizer` lines
- Upload its artifact
- Combine Results & Summary succeeds

## Risk

- **Performance:** `NSLock` acquire/release per `featureFlags` read. Hot paths read it occasionally (twice in `SocialLoginUrlGenerator`, once per `startPostConnectivityServices` call). Microsecond-level overhead — negligible.
- **API surface:** zero public API change. Callers continue using `self.featureFlags = …` and `let x = self.featureFlags` unchanged.
- **Deadlock potential:** the lock guards only property storage. No nested locks, no callbacks under the lock, no async work inside `withLock`. Cannot deadlock.
- **Test flakiness:** the new race test relies on TSan to detect the absence of races. Without TSan it just exercises the property concurrently and must not crash. Deterministic.

## Out-of-scope follow-ups (separate PRs)

1. Apply the same lock-backed pattern to `api` and `entitlements` on `FronteggAuth`. Same reassignment pattern, same race risk during region switches.
2. Cancel in-flight `startPostConnectivityServices` tasks when `featureFlags` (or `api`/`entitlements`) is reassigned, so they don't continue against stale state. Optimisation, not correctness.
3. Once all three properties are protected, drop `continue-on-error: true` from the TSan job in CI (already done by this PR for `featureFlags` alone — but the others may surface new findings).

## PR structure

Single PR. Commit order:

1. `test: add red regression test for FronteggAuth.featureFlags race` (test alone, RED on master)
2. `fix(FronteggAuth): serialize featureFlags reads/writes via NSLock` (the fix, turns RED → GREEN)
3. `ci(tsan): drop continue-on-error now that featureFlags race is fixed` (promote TSan to required)
4. `docs: move featureFlags race to "Past findings" in CONTRIBUTING.md`

Each commit independently revertable. The test+fix split makes red-then-green provable from `git log` alone.
