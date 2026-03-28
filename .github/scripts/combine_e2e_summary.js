#!/usr/bin/env node

"use strict";

const fs = require("node:fs");
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
  const fileMap = new Map(); // path -> { covered, total }

  for (const xc of xcresultPaths) {
    try {
      const out = execSync(`xcrun xccov view --report --files-for-target FronteggSwift "${xc}" 2>/dev/null`, { encoding: "utf8", timeout: 30000 });
      for (const line of out.split("\n")) {
        // Format: "N  /path/to/File.swift  M  X.XX% (covered/total)"
        const match = line.match(/^\s*\d+\s+(\S+\.swift)\s+\d+\s+[\d.]+%\s+\((\d+)\/(\d+)\)/);
        if (match) {
          const [, filePath, covered, total] = match;
          const existing = fileMap.get(filePath);
          const c = parseInt(covered), t = parseInt(total);
          if (!existing || c > existing.covered) {
            fileMap.set(filePath, { covered: c, total: t });
          }
        }
      }
    } catch { /* xcresult may not have FronteggSwift target */ }
  }
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
    folder.files.push({ name: fileName, covered, total, pct: total > 0 ? ((covered / total) * 100).toFixed(1) : "0.0" });
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
    const pct = v.total > 0 ? ((v.covered / v.total) * 100).toFixed(1) : "0.0";
    const bar = pct >= 80 ? "🟢" : pct >= 50 ? "🟡" : "🔴";
    lines.push(`| ${bar} ${esc(folder)} | ${pct}% | ${v.covered}/${v.total} |`);
  }

  // Accordion per folder with file details
  lines.push("");
  for (const [folder, v] of sorted) {
    if (v.files.length === 0) continue;
    const pct = v.total > 0 ? ((v.covered / v.total) * 100).toFixed(1) : "0.0";
    lines.push(`<details><summary>${folder} — ${pct}% (${v.files.length} files)</summary>`, "");
    lines.push("| File | Coverage | Lines |", "| --- | --- | --- |");
    const sortedFiles = v.files.sort((a, b) => a.name.localeCompare(b.name));
    for (const f of sortedFiles) {
      const bar = f.pct >= 80 ? "🟢" : f.pct >= 50 ? "🟡" : "🔴";
      lines.push(`| ${bar} ${esc(f.name)} | ${f.pct}% | ${f.covered}/${f.total} |`);
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

  const lines = ["# Demo E2E Test Results", ""];
  const xcresultPaths = [];

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

  // Coverage from all xcresult bundles
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
