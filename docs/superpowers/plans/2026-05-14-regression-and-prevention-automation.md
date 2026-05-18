# Regression Coverage & Bug-Class Prevention Automation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship one PR that adds regression coverage for FR-24808 / FR-24822 / FR-24598 and broader bug-class prevention (Thread Sanitizer, informational coverage summary, CONTRIBUTING.md).

**Architecture:** Pure additive changes — comments tagging existing tests, one new e2e test, one new CI job, one new CI step, one new doc file. No production code changes. Commits ordered so each is independently revertable.

**Tech Stack:** Swift (XCTest), GitHub Actions YAML, Apple `xcodebuild` / `xccov`, `gh` CLI.

**Spec:** [docs/superpowers/specs/2026-05-14-regression-and-prevention-automation.md](../specs/2026-05-14-regression-and-prevention-automation.md)

---

## Task 1: Tag the FR-24808 mis-routed-callback unit tests

**Files:**
- Modify: `Tests/FronteggSwiftTests/FronteggAuthOAuthCallbackTests.swift:580` (insert `MARK` directly above `test_handleOpenUrl_misroutedCustomSchemeCallbackWithCode_recoversViaTokenExchange` at line 581)

- [ ] **Step 1: Read the surrounding context**

Run: `sed -n '575,585p' Tests/FronteggSwiftTests/FronteggAuthOAuthCallbackTests.swift`
Confirm line 581 is `func test_handleOpenUrl_misroutedCustomSchemeCallbackWithCode_recoversViaTokenExchange() async throws {` and the lines immediately above are either blank or an unrelated test's closing `}`.

- [ ] **Step 2: Insert the section MARK comment**

Insert exactly these two lines immediately above line 581 (the `func test_handleOpenUrl_misroutedCustomSchemeCallbackWithCode_recoversViaTokenExchange` declaration), separated from the preceding content by a blank line:

```swift
    // MARK: - FR-24808 Mis-routed OAuth Callback Recovery Regression Tests
    // Regression: FR-24808 — multi-app AASA scenarios deliver OAuth callbacks
    // to the wrong app via openURL. The SDK must recognize the OAuth-shaped
    // custom-scheme URL and exchange the code instead of rejecting the URL.
```

(Indent with 4 spaces to match the surrounding class-body indentation.)

- [ ] **Step 3: Build to verify nothing broke**

Run:
```bash
xcodebuild build-for-testing \
  -scheme FronteggSwift \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:FronteggSwiftTests 2>&1 | tail -20
```
Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 4: Stage (do not commit yet — commits batched at end of Task 2)**

```bash
git add Tests/FronteggSwiftTests/FronteggAuthOAuthCallbackTests.swift
```

---

## Task 2: Tag the FR-24822 and FR-24598 unit-test sections + commit the tag batch

**Files:**
- Modify: `Tests/FronteggSwiftTests/NetworkStatusMonitorTests.swift:156` (existing `// MARK: - One-shot CheckedContinuation safety (issue #256)`)
- Modify: `Tests/FronteggSwiftTests/CustomWebViewTests.swift:355` (existing `// MARK: - Social-success watchdog no longer reloads`)

- [ ] **Step 1: Update the NetworkStatusMonitor MARK to add FR-24822 tag**

In [Tests/FronteggSwiftTests/NetworkStatusMonitorTests.swift](../../../Tests/FronteggSwiftTests/NetworkStatusMonitorTests.swift), replace the single line at 156:

```swift
    // MARK: - One-shot CheckedContinuation safety (issue #256)
```

with:

```swift
    // MARK: - FR-24822 One-shot CheckedContinuation safety (issue #256)
    // Regression: FR-24822 — NWPathMonitor.pathUpdateHandler can re-enter and
    // resume a CheckedContinuation twice, crashing with EXC_BREAKPOINT. The
    // tests below pin the lock-guarded "first resume wins" bridge.
```

- [ ] **Step 2: Update the CustomWebViewTests MARK to add FR-24598 tag**

In [Tests/FronteggSwiftTests/CustomWebViewTests.swift](../../../Tests/FronteggSwiftTests/CustomWebViewTests.swift), replace the single line at 355:

```swift
    // MARK: - Social-success watchdog no longer reloads
```

with:

```swift
    // MARK: - FR-24598 Social-success watchdog no longer reloads
    // Regression: FR-24598 — reloading /oauth/account/social/success caused
    // the authorization code to be re-consumed. The watchdog must never reload;
    // it only hides the SDK loader. These tests pin the pure decision logic.
```

- [ ] **Step 3: Build to verify**

```bash
xcodebuild build-for-testing \
  -scheme FronteggSwift \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:FronteggSwiftTests 2>&1 | tail -10
```
Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 4: Run the existing tests to confirm comments did not break anything**

```bash
xcodebuild test \
  -scheme FronteggSwift \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:FronteggSwiftTests/NetworkStatusMonitorTests \
  -only-testing:FronteggSwiftTests/CustomWebViewTests \
  -only-testing:FronteggSwiftTests/FronteggAuthOAuthCallbackTests 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **` and no failures.

- [ ] **Step 5: Commit**

```bash
git add Tests/FronteggSwiftTests/NetworkStatusMonitorTests.swift Tests/FronteggSwiftTests/CustomWebViewTests.swift
git commit -m "$(cat <<'EOF'
test: tag regression tests with FR-24808 / FR-24822 / FR-24598

Adds section MARK comments linking each regression-test cluster to its
Frontegg ticket, making future readers able to trace tests back to the
bug they guard. Convention will be documented in CONTRIBUTING.md.

- FR-24808: mis-routed OAuth callback recovery (PR #257)
- FR-24822: NWPathMonitor CheckedContinuation double-resume (PR #258)
- FR-24598: social-success watchdog no-reload contract (PR #259)
EOF
)"
```

---

## Task 3: Add the FR-24598 e2e regression test (social-success watchdog no-reload)

**Files:**
- Modify: `demo-embedded/demo-embedded-e2e/DemoEmbeddedE2ETests.swift:725-746` (add section MARK on existing FR-24808 anchor + new test method below `testEmbeddedGoogleSocialLoginWithSystemWebAuthenticationSession` at line 131)
- Modify: `demo-embedded/demo-embedded-e2e/scenario-catalog.json` (add entry)

- [ ] **Step 1: Update the existing deep-link section MARK to include the FR ticket**

In [demo-embedded/demo-embedded-e2e/DemoEmbeddedE2ETests.swift](../../../demo-embedded/demo-embedded-e2e/DemoEmbeddedE2ETests.swift), replace line 726:

```swift
    // MARK: - Deep-link recovery regression (multi-app AASA wrong-app routing)
```

with:

```swift
    // MARK: - FR-24808 Deep-link recovery regression (multi-app AASA wrong-app routing)
```

- [ ] **Step 2: Insert the new social-success watchdog e2e test**

Insert immediately after the closing `}` of `testEmbeddedGoogleSocialLoginWithSystemWebAuthenticationSession` at line 131 (before the blank line that precedes `testEmbeddedGoogleSocialLoginSupportsBasePathRootCallbackAlias`). The test mirrors the system-web-auth login flow, then verifies the watchdog does not reload the success page after the 5-second `socialSuccessWatchdogDelay`:

```swift

    // Regression: FR-24598 — the social-success watchdog must never reload
    // /oauth/account/social/success, because reloading re-consumes the
    // authorization code and surfaces a generic OAuth error. The watchdog
    // only hides the SDK loader. CustomWebViewTests.swift pins the pure
    // SocialSuccessWatchdogAction logic; this test pins the integration.
    func testEmbeddedGoogleSocialSuccessWatchdogDoesNotReloadSuccessPage() throws {
        launchApp(resetState: true, useTestingWebAuthenticationTransport: false)
        waitForScreen("LoginPageRoot")
        tapButton("E2EEmbeddedGoogleSocialButton")

        acceptSystemDialogIfNeeded(timeout: 10)
        XCTAssertTrue(Self.server.waitForRequest(path: "/idp/google/authorize", timeout: 10))

        app.getWebLabel("Mock Google Login").waitUntilExists(timeout: 20)
        app.getWebButton("Continue with Mock Google").safeTap()
        acceptSystemDialogIfNeeded(timeout: 10)
        waitForUserEmail("google-social@frontegg.com", timeout: 30)

        // The success page was hit once during the real login flow.
        XCTAssertTrue(
            Self.server.waitForRequestCount(path: "/oauth/account/social/success", count: 1, timeout: 20),
            "Expected the embedded webview to hit /oauth/account/social/success exactly once during login."
        )

        // Wait past the 5s socialSuccessWatchdogDelay defined in
        // Sources/FronteggSwift/embedded/CustomWebView.swift. If the watchdog
        // reloads the success page (the FR-24598 bug), requestCount would
        // increment to 2.
        Thread.sleep(forTimeInterval: 6)

        XCTAssertEqual(
            Self.server.requestCount(path: "/oauth/account/social/success"),
            1,
            "Watchdog must not reload /oauth/account/social/success — reloading re-consumes the authorization code (FR-24598)."
        )
    }
```

- [ ] **Step 3: Add scenario-catalog entry**

In [demo-embedded/demo-embedded-e2e/scenario-catalog.json](../../../demo-embedded/demo-embedded-e2e/scenario-catalog.json), insert a new entry into the `"tests"` array immediately after the existing `testEmbeddedGoogleSocialLoginWithSystemWebAuthenticationSession` entry (before the basePath alias entries — match the source-file order). Use exactly this entry:

```json
    {
      "method": "testEmbeddedGoogleSocialSuccessWatchdogDoesNotReloadSuccessPage",
      "title": "Embedded Google social-success watchdog does not reload the success page",
      "description": "Drives the embedded Google social flow through to /oauth/account/social/success, waits past the 5s watchdog delay, and verifies the watchdog never reloads the success page (which would re-consume the authorization code) and the user remains authenticated."
    },
```

Take care: JSON requires a trailing comma after the new entry because more entries follow. Verify with `python3 -m json.tool demo-embedded/demo-embedded-e2e/scenario-catalog.json > /dev/null` — exit code 0 means valid JSON.

- [ ] **Step 4: Build the e2e test target**

```bash
xcodebuild build-for-testing \
  -project demo-embedded/demo-embedded.xcodeproj \
  -scheme demo-embedded \
  -destination "platform=iOS Simulator,name=iPhone 16 Pro" 2>&1 | tail -20
```
Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 5: Run the new e2e test locally — expect PASS (bug is fixed)**

```bash
xcodebuild test \
  -project demo-embedded/demo-embedded.xcodeproj \
  -scheme demo-embedded \
  -destination "platform=iOS Simulator,name=iPhone 16 Pro" \
  -only-testing:demo-embedded-e2e/DemoEmbeddedE2ETests/testEmbeddedGoogleSocialSuccessWatchdogDoesNotReloadSuccessPage 2>&1 | tail -30
```
Expected: `Test Case '-[demo_embedded_e2e.DemoEmbeddedE2ETests testEmbeddedGoogleSocialSuccessWatchdogDoesNotReloadSuccessPage]' passed`.

- [ ] **Step 6: Verify the test would catch a regression (red-then-green)**

Temporarily reintroduce the bug to confirm the test fails. In [Sources/FronteggSwift/embedded/CustomWebView.swift](../../../Sources/FronteggSwift/embedded/CustomWebView.swift), find the watchdog work-item builder around line 110 (`makeSocialSuccessWatchdogWorkItem`). Inside the work item, replace the `hideLoader` branch with a `webView.load(URLRequest(url: url))` call (intentionally re-introducing the reload). Run the test again:

```bash
xcodebuild test \
  -project demo-embedded/demo-embedded.xcodeproj \
  -scheme demo-embedded \
  -destination "platform=iOS Simulator,name=iPhone 16 Pro" \
  -only-testing:demo-embedded-e2e/DemoEmbeddedE2ETests/testEmbeddedGoogleSocialSuccessWatchdogDoesNotReloadSuccessPage 2>&1 | tail -20
```
Expected: test FAILS with the message `Watchdog must not reload /oauth/account/social/success — reloading re-consumes the authorization code (FR-24598).`.

Revert the change with `git checkout -- Sources/FronteggSwift/embedded/CustomWebView.swift` and re-run the test — must now pass again.

- [ ] **Step 7: Commit**

```bash
git add demo-embedded/demo-embedded-e2e/DemoEmbeddedE2ETests.swift demo-embedded/demo-embedded-e2e/scenario-catalog.json
git commit -m "$(cat <<'EOF'
test(e2e): pin FR-24598 social-success watchdog no-reload contract

Adds testEmbeddedGoogleSocialSuccessWatchdogDoesNotReloadSuccessPage to
the embedded e2e suite. Unit tests in CustomWebViewTests pin the pure
SocialSuccessWatchdogAction logic; this test pins the integration so
future re-wires that bypass the action are caught.

The test drives the real Google social flow through ASWebAuthenticationSession,
waits past the 5s socialSuccessWatchdogDelay, and asserts the success
page was hit exactly once (no reload).

Also tags the existing testMisroutedOpenURLRecoversIntoAuthenticatedState
section with FR-24808 for traceability.
EOF
)"
```

---

## Task 4: Add the Thread Sanitizer CI job

**Files:**
- Modify: `.github/workflows/demo-e2e.yml` (add `unit-tests-tsan` job; update `summary.needs`)

- [ ] **Step 1: Add the new TSan job**

In [.github/workflows/demo-e2e.yml](../../../.github/workflows/demo-e2e.yml), insert this new job immediately after the existing `unit-tests:` job block (i.e., after the existing `unit-tests` artifact-upload step, before `matrix-setup:`). Use exactly this YAML, preserving 2-space indentation:

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

- [ ] **Step 2: Add `unit-tests-tsan` to the `summary` job's `needs:` list**

Find the existing `summary:` job near the end of the file. The current `needs:` line is:

```yaml
    needs: [matrix-setup, e2e, unit-tests]
```

Replace with:

```yaml
    needs: [matrix-setup, e2e, unit-tests, unit-tests-tsan]
```

- [ ] **Step 3: Append a TSan section to the summary job (after the existing combine step)**

Inside the `summary:` job's `steps:` array, add this step immediately after the existing `Generate combined summary` step:

```yaml
      - name: Append Thread Sanitizer summary
        if: always()
        run: |
          set -e
          {
            echo ""
            echo "## Thread Sanitizer"
            echo ""
            if [ -f "${{ runner.temp }}/artifacts/unit-tests-tsan-results/unit-tests-tsan.log" ]; then
              if grep -qE "ThreadSanitizer: data race|WARNING: ThreadSanitizer" \
                "${{ runner.temp }}/artifacts/unit-tests-tsan-results/unit-tests-tsan.log"; then
                echo ":x: ThreadSanitizer reported data races. See \`unit-tests-tsan-results\` artifact."
              else
                echo ":white_check_mark: No data races reported."
              fi
            else
              echo ":warning: No TSan log found."
            fi
          } >> "$GITHUB_STEP_SUMMARY"
```

Also add the TSan artifacts to the download step at the start of the `summary` job. Find:

```yaml
      - name: Download unit test artifacts
        uses: actions/download-artifact@v8
        with:
          name: unit-tests-results
          path: ${{ runner.temp }}/artifacts/unit-tests-results
```

Add this step immediately after it:

```yaml
      - name: Download Thread Sanitizer artifacts
        uses: actions/download-artifact@v8
        if: always()
        with:
          name: unit-tests-tsan-results
          path: ${{ runner.temp }}/artifacts/unit-tests-tsan-results
```

- [ ] **Step 4: Validate the YAML syntax**

```bash
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/demo-e2e.yml')); print('OK')"
```
Expected: `OK` (exit 0). If yaml is not installed, fall back to `gh workflow view demo-e2e.yml --yaml 2>/dev/null || echo 'gh check'`.

- [ ] **Step 5: Run the same xcodebuild command locally to verify TSan works on this suite**

```bash
xcodebuild test \
  -scheme FronteggSwift \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:FronteggSwiftTests \
  -enableThreadSanitizer YES \
  -enableCodeCoverage NO \
  -parallel-testing-enabled NO 2>&1 | tee /tmp/local-tsan.log | tail -30
```
Expected: `** TEST SUCCEEDED **` and no `ThreadSanitizer: data race` lines in `/tmp/local-tsan.log`. If TSan reports a race in unrelated code, STOP and report the finding — that's a separate bug. Either fix it, suppress narrowly, or change this job's gating to advisory before continuing.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/demo-e2e.yml
git commit -m "$(cat <<'EOF'
ci: add Thread Sanitizer unit-test job

Adds unit-tests-tsan as a parallel job to demo-e2e.yml. Runs the
FronteggSwift unit-test suite with -enableThreadSanitizer YES on every
PR. Coverage is disabled in this job (TSan and coverage are mutually
exclusive); the existing unit-tests job still produces coverage.

Rationale: PR #258 (FR-24822) was a CheckedContinuation re-entrance
race in NWPathMonitor that crashed with EXC_BREAKPOINT. The unit test
in NetworkStatusMonitorTests catches the known case; TSan catches the
class of bug going forward.

Starts as a required check. If real-world flakiness emerges, follow-up
will downgrade to advisory or add narrow suppressions.
EOF
)"
```

---

## Task 5: Add per-file coverage summary as a sticky PR comment

**Files:**
- Modify: `.github/workflows/demo-e2e.yml` (add new step in `summary:` job)

- [ ] **Step 1: Add coverage extraction + comment step to the `summary:` job**

In [.github/workflows/demo-e2e.yml](../../../.github/workflows/demo-e2e.yml), in the `summary:` job, add this step immediately after the `Append Thread Sanitizer summary` step from Task 4:

```yaml
      - name: Build per-file coverage summary
        id: coverage_summary
        if: github.event_name == 'pull_request'
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          set +e

          XCRESULT="${{ runner.temp }}/artifacts/unit-tests-results/unit-tests.xcresult"
          if [ ! -d "$XCRESULT" ]; then
            echo "No xcresult bundle at $XCRESULT — skipping coverage summary."
            exit 0
          fi

          COVERAGE_JSON="${{ runner.temp }}/coverage.json"
          xcrun xccov view --report --files-for-target FronteggSwift --json "$XCRESULT" > "$COVERAGE_JSON" 2>/dev/null
          if [ ! -s "$COVERAGE_JSON" ]; then
            echo "xccov produced empty output — skipping coverage summary."
            exit 0
          fi

          git fetch --depth=1 origin master 2>/dev/null || true
          CHANGED="${{ runner.temp }}/changed-files.txt"
          git diff --name-only origin/master...HEAD | grep '^Sources/FronteggSwift/.*\.swift$' > "$CHANGED" || true

          if [ ! -s "$CHANGED" ]; then
            echo "No FronteggSwift source files changed — skipping coverage summary."
            exit 0
          fi

          BODY="${{ runner.temp }}/coverage-comment.md"
          {
            echo "<!-- coverage-summary -->"
            echo "## Coverage for changed FronteggSwift files"
            echo ""
            echo "| File | Line coverage | Covered / Total |"
            echo "|------|---------------|-----------------|"
            while IFS= read -r file; do
              # xccov keys files by absolute path on the runner; match by basename suffix.
              base=$(basename "$file")
              row=$(node -e "
                const fs = require('fs');
                const data = JSON.parse(fs.readFileSync('$COVERAGE_JSON', 'utf8'));
                const files = Array.isArray(data) ? data : (data.files || []);
                const match = files.find(f => (f.path || f.name || '').endsWith('/$base') || (f.path || f.name || '') === '$base');
                if (!match) { process.stdout.write('| $file | n/a | n/a |'); return; }
                const pct = (match.lineCoverage * 100).toFixed(1);
                const covered = match.coveredLines ?? 'n/a';
                const total = match.executableLines ?? 'n/a';
                process.stdout.write(\`| $file | \${pct}% | \${covered} / \${total} |\`);
              " 2>/dev/null)
              if [ -z "$row" ]; then
                echo "| $file | n/a | n/a |"
              else
                echo "$row"
              fi
            done < "$CHANGED"
            echo ""
            echo "_Informational — no threshold is enforced. Coverage is for the \`FronteggSwift\` target unit-test run._"
          } > "$BODY"

          cat "$BODY" >> "$GITHUB_STEP_SUMMARY"
          echo "body_path=$BODY" >> "$GITHUB_OUTPUT"

      - name: Post or update coverage PR comment
        if: github.event_name == 'pull_request' && steps.coverage_summary.outputs.body_path != ''
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          PR_NUMBER: ${{ github.event.pull_request.number }}
          BODY_PATH: ${{ steps.coverage_summary.outputs.body_path }}
        run: |
          set -e

          # Find an existing comment with our marker.
          EXISTING_ID=$(gh api \
            "repos/${{ github.repository }}/issues/${PR_NUMBER}/comments" \
            --paginate \
            --jq '.[] | select(.body | contains("<!-- coverage-summary -->")) | .id' \
            | head -n 1)

          if [ -n "$EXISTING_ID" ]; then
            gh api \
              --method PATCH \
              "repos/${{ github.repository }}/issues/comments/${EXISTING_ID}" \
              --field body="@${BODY_PATH}"
          else
            gh pr comment "${PR_NUMBER}" --body-file "${BODY_PATH}"
          fi
```

- [ ] **Step 2: Validate the YAML syntax**

```bash
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/demo-e2e.yml')); print('OK')"
```
Expected: `OK`.

- [ ] **Step 3: Locally dry-run the xccov + filter logic against an existing xcresult**

If a local xcresult exists from a prior unit-test run, exercise the script-like logic manually to confirm the command shape is right:

```bash
# Generate a fresh xcresult if one is not handy:
xcodebuild test \
  -scheme FronteggSwift \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:FronteggSwiftTests/AuthResponseTests \
  -resultBundlePath /tmp/cov-local.xcresult \
  -enableCodeCoverage YES 2>&1 | tail -5

# Then extract:
xcrun xccov view --report --files-for-target FronteggSwift --json /tmp/cov-local.xcresult > /tmp/cov-local.json
head -c 400 /tmp/cov-local.json
```
Expected: JSON output beginning with `{` or `[`. Inspect a few entries to confirm `lineCoverage`, `coveredLines`, `executableLines`, and `path`/`name` field names — if Apple has changed the schema, adjust the `node -e` extraction in Step 1 accordingly. (The `if (!match) { ... 'n/a' }` fallback already handles the missing-field case without breaking CI.)

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/demo-e2e.yml
git commit -m "$(cat <<'EOF'
ci: post per-file coverage summary as sticky PR comment

Adds a step to the demo-e2e summary job that:
- extracts FronteggSwift target coverage from the unit-test xcresult
- filters to source files changed vs origin/master
- posts a markdown table as a sticky PR comment (HTML marker; updated
  in place on subsequent runs)
- also writes the table to GITHUB_STEP_SUMMARY

Informational only — no threshold. Failure-safe: if xccov output is
empty or no FronteggSwift source files changed, the step skips and CI
continues. xccov field-name fallbacks keep the step resilient to Apple
changing the JSON shape across Xcode versions.
EOF
)"
```

---

## Task 6: Create CONTRIBUTING.md

**Files:**
- Create: `CONTRIBUTING.md` (new file at repo root)

- [ ] **Step 1: Create the file with the three sections from the spec**

Create [CONTRIBUTING.md](../../../CONTRIBUTING.md) with exactly this content:

````markdown
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
````

- [ ] **Step 2: Verify the file is well-formed markdown**

```bash
test -f CONTRIBUTING.md && wc -l CONTRIBUTING.md
```
Expected: file exists and has ~90+ lines.

- [ ] **Step 3: Commit**

```bash
git add CONTRIBUTING.md
git commit -m "$(cat <<'EOF'
docs: add CONTRIBUTING.md with test, regression-convention, and required-check guidance

Documents:
- How to run unit tests, TSan unit tests, and embedded e2e tests locally
  (matching the CI commands in demo-e2e.yml).
- The FR-NNNNN regression-test convention applied in this PR, so future
  regression tests are traceable back to the bugs they guard.
- The list of CI status checks that should be marked required in
  branch-protection rules. (Branch-protection itself is a Settings change
  and not in version control; this doc captures the intent.)
EOF
)"
```

---

## Task 7: Open the pull request

- [ ] **Step 1: Verify the working tree is clean and all commits are present**

```bash
git status
git log --oneline origin/master..HEAD
```
Expected: clean working tree; exactly 6 commits ahead of `origin/master` (1 spec + 5 implementation commits from Tasks 2–6). The implementation commit subjects should be:

1. `test: tag regression tests with FR-24808 / FR-24822 / FR-24598`
2. `test(e2e): pin FR-24598 social-success watchdog no-reload contract`
3. `ci: add Thread Sanitizer unit-test job`
4. `ci: post per-file coverage summary as sticky PR comment`
5. `docs: add CONTRIBUTING.md with test, regression-convention, and required-check guidance`

(Plus the earlier spec commit `docs: add spec for regression coverage + bug-class prevention (#257/#258/#259)`.)

- [ ] **Step 2: Push the branch**

```bash
git push -u origin HEAD
```

- [ ] **Step 3: Open the PR**

```bash
gh pr create \
  --base master \
  --title "Regression coverage + bug-class prevention automation for #257/#258/#259" \
  --body "$(cat <<'EOF'
## Summary

Single PR that adds:

- **Regression coverage** traceable to the three recent fixes (FR-24808, FR-24822, FR-24598)
- **Bug-class prevention** via Thread Sanitizer CI + informational coverage summary
- **CONTRIBUTING.md** with test commands, the FR-NNNNN regression-tag convention, and the list of required status checks maintainers should enable

Design spec: [docs/superpowers/specs/2026-05-14-regression-and-prevention-automation.md](docs/superpowers/specs/2026-05-14-regression-and-prevention-automation.md)

## Changes

- `test:` — tag the existing regression-test clusters with FR-24808 / FR-24822 / FR-24598
- `test(e2e):` — new e2e test `testEmbeddedGoogleSocialSuccessWatchdogDoesNotReloadSuccessPage` that pins the FR-24598 no-reload contract at the integration level (the unit test pins the pure logic)
- `ci:` — new `Unit Tests (Thread Sanitizer)` job, parallel to the existing unit-test job. Coverage is disabled in the TSan job (mutually exclusive); the existing job still produces coverage signal.
- `ci:` — sticky PR comment with per-file coverage for changed `Sources/FronteggSwift/**/*.swift` files. Informational only. Failure-safe (no comment if extraction fails, CI does not break).
- `docs:` — `CONTRIBUTING.md` at repo root.

## Test plan

- [ ] CI: all existing checks still pass
- [ ] CI: new `Unit Tests (Thread Sanitizer)` check passes
- [ ] CI: PR receives a coverage-summary comment with this PR's changed files
- [ ] Manually: maintainer enables the new check in branch protection settings (per CONTRIBUTING.md)

## Out of scope

- Branch-protection rule changes themselves — those are a Settings change, not in version control. CONTRIBUTING.md documents which checks to require.
- Backfilling coverage on legacy code. No coverage threshold is added.
- Production code changes. This PR is pure additive (comments, tests, CI, docs).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 4: Verify the PR was created and link it back**

```bash
gh pr view --web
```

Return the PR URL to the user.

---

## Self-review checklist (already run by author)

- ✅ **Spec coverage:** A1 (Task 3), A2 (Tasks 1 & 2), B1 (Task 4), B2 (Task 5), C1 (Task 6), PR-open (Task 7).
- ✅ **Placeholder scan:** no TBD / TODO / "handle appropriately" left in plan.
- ✅ **Type consistency:** test method names, MARK strings, job names, and artifact names are identical across all tasks where they appear (`unit-tests-tsan` job name, `unit-tests-tsan-results` artifact name, `testEmbeddedGoogleSocialSuccessWatchdogDoesNotReloadSuccessPage` test name, `<!-- coverage-summary -->` marker).
- ✅ **Order:** Task N's commit doesn't depend on Task N+1 — each commit is independently revertable. The only exception: Task 5's coverage step references artifacts produced by the existing `unit-tests` job (unchanged) and is in the same workflow file as Task 4's TSan job, so a `git revert` of Task 5 alone is clean.
