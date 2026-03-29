#!/usr/bin/env node

"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execSync } = require("node:child_process");

// ── Config ──────────────────────────────────────────────────────────────────

const APP_CONFIGS = {
  embedded: { testClass: "DemoEmbeddedE2ETests", catalog: "demo-embedded/demo-embedded-e2e/scenario-catalog.json", label: "Demo Embedded" },
  "multi-region": { testClass: "MultiRegionE2ETests", catalog: "demo-multi-region/demo-multi-region-e2e/scenario-catalog.json", label: "Demo Multi-Region" },
  uikit: { testClass: "UIKitE2ETests", catalog: "demo-uikit/demo-uikit-e2e/scenario-catalog.json", label: "Demo UIKit" },
};

const ANSI = /\x1b\[[0-9;]*m/g;
const TOKEN_RE = /[A-Z]+(?=[A-Z][a-z]|[0-9]|$)|[A-Z]?[a-z]+|[0-9]+/g;
const TOKEN_MAP = { api: "API", id: "ID", oauth: "OAuth", oidc: "OIDC", saml: "SAML", sso: "SSO", ui: "UI", url: "URL" };

// ── Helpers ─────────────────────────────────────────────────────────────────

function parseArgs(argv) {
  const o = {};
  for (let i = 0; i < argv.length; i += 1) {
    if (!argv[i].startsWith("--")) throw new Error(`Unexpected: ${argv[i]}`);
    const k = argv[i].slice(2);
    const v = argv[++i];
    if (!v || v.startsWith("--")) throw new Error(`Missing value for --${k}`);
    o[k] = v;
  }
  for (const k of ["artifacts-dir", "summary"]) if (!o[k]) throw new Error(`Missing --${k}`);
  return o;
}

function strip(s) { return s.replace(ANSI, ""); }
function esc(s) { return String(s).replace(/\|/g, "\\|").replace(/\r?\n/g, " ").trim(); }
function humanize(m) {
  const w = m.startsWith("test") && m.length > 4 ? m.slice(4) : m;
  const t = w.match(TOKEN_RE);
  return t ? t.map(tk => TOKEN_MAP[tk.toLowerCase()] || tk.charAt(0).toUpperCase() + tk.slice(1).toLowerCase()).join(" ") : w;
}

// ── Catalog ─────────────────────────────────────────────────────────────────

function loadCatalog(p) {
  try {
    const raw = JSON.parse(fs.readFileSync(p, "utf8"));
    const entries = raw.tests || raw.scenarios || [];
    const scenarios = [], lookup = new Map();
    for (const e of entries) {
      const s = { method: e.method, title: e.title || humanize(e.method), description: e.description || "" };
      scenarios.push(s);
      lookup.set(e.method, s);
    }
    return { scenarios, lookup };
  } catch { return { scenarios: [], lookup: new Map() }; }
}

// ── Log parsing ─────────────────────────────────────────────────────────────

function parseLog(logPath, testClass) {
  const escaped = testClass.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const tcRe = new RegExp(`^Test Case '-\\[[^ ]+\\.${escaped} (?<method>[^\\]]+)]' (?<status>started|passed|failed)(?: \\((?<duration>[0-9.]+) seconds\\))?\\.$`);
  const failRe = new RegExp(`^.+error: -\\[[^ ]+\\.${escaped} (?<method>[^\\]]+)] : (?<message>.+)$`);

  const results = new Map();
  const order = [];
  for (const raw of fs.readFileSync(logPath, "utf8").split(/\r?\n/)) {
    const line = strip(raw).trim();
    if (!line) continue;
    const tm = line.match(tcRe);
    if (tm) {
      const { method, status, duration } = tm.groups;
      let t = results.get(method);
      if (!t) { t = { method, status: "incomplete", dur: null, fail: null }; results.set(method, t); order.push(method); }
      if (status !== "started") { t.status = status; if (duration) t.dur = parseFloat(duration); }
      continue;
    }
    const fm = line.match(failRe);
    if (fm) {
      const { method, message } = fm.groups;
      let t = results.get(method);
      if (!t) { t = { method, status: "incomplete", dur: null, fail: null }; results.set(method, t); order.push(method); }
      if (!t.fail) t.fail = message.trim();
    }
  }
  return { order, results };
}

function mergeResults(allParsed) {
  const merged = new Map();
  const order = [];
  for (const p of allParsed) {
    for (const m of p.order) {
      if (!merged.has(m)) { merged.set(m, p.results.get(m)); order.push(m); }
    }
  }
  return { order, results: merged };
}

// ── Coverage ────────────────────────────────────────────────────────────────

function extractCoverage(xcresultPaths) {
  if (xcresultPaths.length === 0) return new Map();

  let reportPath;
  if (xcresultPaths.length === 1) {
    reportPath = xcresultPaths[0];
  } else {
    // Merge all xcresult bundles for true combined coverage
    const mergedPath = path.join(os.tmpdir(), `combined-${Date.now()}.xcresult`);
    const quotedPaths = xcresultPaths.map(p => `"${p}"`).join(" ");
    try {
      execSync(
        `xcrun xcresulttool merge ${quotedPaths} --output-path "${mergedPath}"`,
        { timeout: 120000 }
      );
      reportPath = mergedPath;
    } catch (e) {
      console.error("xcresulttool merge failed, falling back to individual reports:", e.message || e);
      // Fallback: extract from each individually, take best per file
      return extractCoverageFallback(xcresultPaths);
    }
  }

  return extractCoverageFromBundle(reportPath);
}

function extractCoverageFallback(xcresultPaths) {
  const fileMap = new Map();
  for (const xc of xcresultPaths) {
    for (const [filePath, data] of extractCoverageFromBundle(xc)) {
      const existing = fileMap.get(filePath);
      if (!existing || data.covered > existing.covered) {
        fileMap.set(filePath, data);
      }
    }
  }
  return fileMap;
}

function extractCoverageFromBundle(xcresultPath) {
  const fileMap = new Map();
  try {
    const out = execSync(`xcrun xccov view --report --files-for-target FronteggSwift "${xcresultPath}" 2>/dev/null`, { encoding: "utf8", timeout: 30000 });
    for (const line of out.split("\n")) {
      const match = line.match(/^\s*\d+\s+(\S+\.swift)\s+\d+\s+[\d.]+%\s+\((\d+)\/(\d+)\)/);
      if (match) {
        const [, filePath, covered, total] = match;
        fileMap.set(filePath, { covered: parseInt(covered), total: parseInt(total) });
      }
    }
  } catch { /* xcresult may not have FronteggSwift target */ }
  return fileMap;
}

function groupCoverageByFolder(fileMap) {
  const folders = new Map(); // folder -> { covered, total, files: [] }
  for (const [filePath, { covered, total }] of fileMap) {
    const parts = filePath.split("/");
    const srcIdx = parts.indexOf("FronteggSwift");
    if (srcIdx < 0) continue;
    const sub = parts.slice(srcIdx + 1, -1).join("/") || "(root)";
    const fileName = parts[parts.length - 1];

    let folder = folders.get(sub);
    if (!folder) { folder = { covered: 0, total: 0, files: [] }; folders.set(sub, folder); }
    folder.covered += covered;
    folder.total += total;
    folder.files.push({ name: fileName, covered, total, pct: total > 0 ? (covered / total) * 100 : 0 });
  }
  return folders;
}

// ── Rendering ───────────────────────────────────────────────────────────────

function renderTestSection(appLabel, catalogLookup, order, results) {
  const lines = [];
  if (order.length === 0) {
    lines.push(`No test executions recorded for ${appLabel}.`);
    return lines.join("\n");
  }

  const ordered = [...order];
  const passed = ordered.filter(m => results.get(m).status === "passed").length;
  const failed = ordered.filter(m => results.get(m).status === "failed").length;
  const incomplete = ordered.filter(m => results.get(m).status === "incomplete").length;

  const icon = failed > 0 ? "❌" : incomplete > 0 ? "⚠️" : "✅";
  lines.push(`${icon} **${ordered.length}** scenarios — ${passed} passed, ${failed} failed, ${incomplete} incomplete`);
  lines.push("", "| Status | Scenario | Duration | Description |", "| --- | --- | --- | --- |");

  for (const m of ordered) {
    const r = results.get(m);
    const s = catalogLookup.get(m) || { title: humanize(m), description: "" };
    const si = { passed: "✅", failed: "❌", incomplete: "⚠️" }[r.status];
    const dur = r.dur !== null ? `${r.dur.toFixed(1)}s` : "";
    lines.push(`| ${si} | ${esc(s.title)}<br><code>${esc(m)}</code> | ${dur} | ${esc(s.description)} |`);
  }

  const failing = ordered.filter(m => { const s = results.get(m).status; return s === "failed" || s === "incomplete"; });
  if (failing.length > 0) {
    lines.push("", "<details><summary>Failure Details</summary>", "");
    for (const m of failing) {
      const r = results.get(m);
      const s = catalogLookup.get(m) || { title: humanize(m) };
      lines.push(`- **${s.title}** (\`${m}\`): ${r.fail || "No excerpt found"}`);
    }
    lines.push("", "</details>");
  }

  return lines.join("\n");
}

function renderCoverage(folders) {
  if (folders.size === 0) return "";

  const lines = ["## Code Coverage (FronteggSwift)", ""];
  let totalCovered = 0, totalAll = 0;

  const sorted = [...folders.entries()].sort((a, b) => a[0].localeCompare(b[0]));
  for (const [, v] of sorted) { totalCovered += v.covered; totalAll += v.total; }
  const totalPct = totalAll > 0 ? ((totalCovered / totalAll) * 100).toFixed(1) : "0.0";

  lines.push(`**Overall: ${totalPct}%** (${totalCovered}/${totalAll} lines)`);
  lines.push("", "| Folder | Coverage | Lines |", "| --- | --- | --- |");

  for (const [folder, v] of sorted) {
    const pct = v.total > 0 ? (v.covered / v.total) * 100 : 0;
    const bar = pct >= 80 ? "🟢" : pct >= 50 ? "🟡" : "🔴";
    lines.push(`| ${bar} ${esc(folder)} | ${pct.toFixed(1)}% | ${v.covered}/${v.total} |`);
  }

  // Accordion per folder with file details
  lines.push("");
  for (const [folder, v] of sorted) {
    if (v.files.length === 0) continue;
    const pct = v.total > 0 ? (v.covered / v.total) * 100 : 0;
    lines.push(`<details><summary>${folder} — ${pct.toFixed(1)}% (${v.files.length} files)</summary>`, "");
    lines.push("| File | Coverage | Lines |", "| --- | --- | --- |");
    const sortedFiles = v.files.sort((a, b) => a.name.localeCompare(b.name));
    for (const f of sortedFiles) {
      const bar = f.pct >= 80 ? "🟢" : f.pct >= 50 ? "🟡" : "🔴";
      lines.push(`| ${bar} ${esc(f.name)} | ${f.pct.toFixed(1)}% | ${f.covered}/${f.total} |`);
    }
    lines.push("", "</details>");
  }

  return lines.join("\n");
}

// ── Unit Tests ──────────────────────────────────────────────────────────────

function parseUnitTestLog(logPath) {
  const tcRe = /^Test Case '-\[[^ ]+ (?<method>[^\]]+)]' (?<status>started|passed|failed)(?: \((?<duration>[0-9.]+) seconds\))?\.$/;
  const suiteStartRe = /^Test Suite '(?<suite>[^']+)' started/;
  const failRe = /^.+error: -\[[^ ]+ (?<method>[^\]]+)] : (?<message>.+)$/;

  const classes = new Map(); // className -> { passed, failed, incomplete, tests: [] }
  let currentClass = null;

  for (const raw of fs.readFileSync(logPath, "utf8").split(/\r?\n/)) {
    const line = strip(raw).trim();
    if (!line) continue;

    const sm = line.match(suiteStartRe);
    if (sm && sm.groups.suite !== "All tests" && sm.groups.suite !== "Selected tests" && !sm.groups.suite.endsWith(".xctest")) {
      currentClass = sm.groups.suite;
      if (!classes.has(currentClass)) {
        classes.set(currentClass, { passed: 0, failed: 0, incomplete: 0, tests: [] });
      }
      continue;
    }

    const tm = line.match(tcRe);
    if (tm) {
      const { method, status, duration } = tm.groups;
      if (status === "started") continue;
      const cls = classes.get(currentClass) || { passed: 0, failed: 0, incomplete: 0, tests: [] };
      if (!classes.has(currentClass)) classes.set(currentClass || "Unknown", cls);
      cls[status === "passed" ? "passed" : "failed"]++;
      cls.tests.push({ method, status, dur: duration ? parseFloat(duration) : null, fail: null });
      continue;
    }

    const fm = line.match(failRe);
    if (fm) {
      const { method, message } = fm.groups;
      const cls = classes.get(currentClass);
      if (cls) {
        const test = cls.tests.find(t => t.method === method);
        if (test && !test.fail) test.fail = message.trim();
      }
    }
  }

  return classes;
}

function renderUnitTestSection(classes) {
  const lines = [];
  let totalPassed = 0, totalFailed = 0;

  for (const [, cls] of classes) {
    totalPassed += cls.passed;
    totalFailed += cls.failed;
  }
  const total = totalPassed + totalFailed;

  if (total === 0) {
    lines.push("No unit test executions recorded.");
    return lines.join("\n");
  }

  const icon = totalFailed > 0 ? "❌" : "✅";
  lines.push(`${icon} **${total}** tests — ${totalPassed} passed, ${totalFailed} failed`);

  // Collapsible per-class breakdown
  const sorted = [...classes.entries()].sort((a, b) => a[0].localeCompare(b[0]));
  lines.push("");
  lines.push("<details><summary>Per-class breakdown</summary>", "");
  lines.push("| Status | Test Class | Passed | Failed |", "| --- | --- | --- | --- |");
  for (const [name, cls] of sorted) {
    const si = cls.failed > 0 ? "❌" : "✅";
    lines.push(`| ${si} | ${esc(name)} | ${cls.passed} | ${cls.failed} |`);
  }
  lines.push("", "</details>");

  // Failure details
  const failures = [];
  for (const [name, cls] of sorted) {
    for (const t of cls.tests) {
      if (t.status === "failed") failures.push({ className: name, ...t });
    }
  }
  if (failures.length > 0) {
    lines.push("", "<details><summary>Failure Details</summary>", "");
    for (const f of failures) {
      lines.push(`- **${f.className}.${f.method}**: ${f.fail || "No excerpt found"}`);
    }
    lines.push("", "</details>");
  }

  return lines.join("\n");
}

// ── Main ────────────────────────────────────────────────────────────────────

function main() {
  const opts = parseArgs(process.argv.slice(2));
  const artifactsDir = opts["artifacts-dir"];
  const appsInput = opts["apps"] || "embedded,multi-region,uikit";
  const apps = appsInput.split(",").map(s => s.trim()).filter(s => APP_CONFIGS[s]);
  const includeUnitTests = opts["include-unit-tests"] === "true";

  const lines = ["# Test Results", ""];
  const xcresultPaths = [];

  // ── Unit Tests ──
  if (includeUnitTests) {
    const unitDir = path.join(artifactsDir, "unit-tests-results");
    if (fs.existsSync(unitDir)) {
      // Collect unit test xcresult for coverage
      const unitXcresults = fs.readdirSync(unitDir).filter(f => f.endsWith(".xcresult"));
      for (const xc of unitXcresults) xcresultPaths.push(path.join(unitDir, xc));

      // Parse unit test log for results
      const unitLogs = fs.readdirSync(unitDir).filter(f => f.endsWith(".log"));
      let unitClasses = new Map();
      for (const log of unitLogs) {
        const parsed = parseUnitTestLog(path.join(unitDir, log));
        for (const [name, cls] of parsed) {
          unitClasses.set(name, cls);
        }
      }

      lines.push("## Unit Tests");
      lines.push("");
      lines.push(renderUnitTestSection(unitClasses));
      lines.push("");
    }
  }

  // ── E2E Tests ──
  lines.push("## E2E Tests");
  lines.push("");

  for (const app of apps) {
    const config = APP_CONFIGS[app];
    const { lookup } = loadCatalog(config.catalog);

    // Find all shard artifacts for this app
    const shardDirs = fs.readdirSync(artifactsDir)
      .filter(d => d.startsWith(`${app}-e2e-shard-`) && d.endsWith("-results"))
      .sort((a, b) => a.localeCompare(b, undefined, { numeric: true }))
      .map(d => path.join(artifactsDir, d));

    // Parse all log files and merge
    const allParsed = [];
    for (const dir of shardDirs) {
      const logs = fs.readdirSync(dir)
        .filter(f => f.endsWith(".log"))
        .sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
      for (const log of logs) {
        allParsed.push(parseLog(path.join(dir, log), config.testClass));
      }
      // Collect xcresult paths
      const xcresults = fs.readdirSync(dir)
        .filter(f => f.endsWith(".xcresult"))
        .sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
      for (const xc of xcresults) xcresultPaths.push(path.join(dir, xc));
    }

    const merged = mergeResults(allParsed);

    lines.push(`### ${config.label}`);
    lines.push("");
    lines.push(renderTestSection(config.label, lookup, merged.order, merged.results));
    lines.push("");
  }

  // Combined coverage from all xcresult bundles (unit + E2E)
  const fileMap = extractCoverage(xcresultPaths);
  const folders = groupCoverageByFolder(fileMap);
  const coverageSection = renderCoverage(folders);
  if (coverageSection) {
    lines.push("---", "");
    lines.push(coverageSection);
  }

  const summary = lines.join("\n") + "\n";
  fs.mkdirSync(path.dirname(opts.summary), { recursive: true });
  fs.writeFileSync(opts.summary, summary, "utf8");
}

try { main(); } catch (e) { console.error(e instanceof Error ? e.message : String(e)); process.exitCode = 1; }
