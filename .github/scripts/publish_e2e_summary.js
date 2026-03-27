#!/usr/bin/env node

"use strict";

const fs = require("node:fs");
const path = require("node:path");

const ANSI_ESCAPE_PATTERN = /\x1b\[[0-9;]*m/g;
const FALLBACK_DESCRIPTION = "Description missing from scenario-catalog.json";
const TOKEN_PATTERN = /[A-Z]+(?=[A-Z][a-z]|[0-9]|$)|[A-Z]?[a-z]+|[0-9]+/g;
const TOKEN_OVERRIDES = {
  api: "API", id: "ID", idp: "IdP", oauth: "OAuth", oidc: "OIDC",
  saml: "SAML", sso: "SSO", ui: "UI", url: "URL",
};

function parseArgs(argv) {
  const options = {};
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (!arg.startsWith("--")) throw new Error(`Unexpected argument: ${arg}`);
    const key = arg.slice(2);
    const value = argv[i + 1];
    if (!value || value.startsWith("--")) throw new Error(`Missing value for --${key}`);
    options[key] = value;
    i += 1;
  }
  for (const k of ["log", "catalog", "summary"]) {
    if (!options[k]) throw new Error(`Missing required argument --${k}`);
  }
  return options;
}

function buildPatterns(testClass) {
  const escaped = testClass.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return {
    testCase: new RegExp(
      `^Test Case '-\\[[^ ]+\\.${escaped} (?<method>[^\\]]+)]' (?<status>started|passed|failed)(?: \\((?<duration>[0-9.]+) seconds\\))?\\.$`
    ),
    failure: new RegExp(
      `^.+error: -\\[[^ ]+\\.${escaped} (?<method>[^\\]]+)] : (?<message>.+)$`
    ),
  };
}

function stripAnsi(v) { return v.replace(ANSI_ESCAPE_PATTERN, ""); }
function escapeCell(v) { return String(v).replace(/\|/g, "\\|").replace(/\r?\n/g, " ").trim(); }

function titleizeToken(t) {
  const o = TOKEN_OVERRIDES[t.toLowerCase()];
  return o || t.charAt(0).toUpperCase() + t.slice(1).toLowerCase();
}

function humanize(method) {
  const w = method.startsWith("test") && method.length > 4 ? method.slice(4) : method;
  const tokens = w.match(TOKEN_PATTERN);
  return tokens ? tokens.map(titleizeToken).join(" ") : w;
}

function loadCatalog(catalogPath) {
  const raw = JSON.parse(fs.readFileSync(catalogPath, "utf8"));
  const entries = raw.tests || raw.scenarios || [];
  if (!Array.isArray(entries)) throw new Error("Catalog must contain 'tests' or 'scenarios' array");
  const scenarios = [];
  const lookup = new Map();
  for (const e of entries) {
    if (!e?.method) throw new Error("Each entry must have 'method'");
    const s = { method: e.method, title: e.title || humanize(e.method), description: e.description || FALLBACK_DESCRIPTION };
    scenarios.push(s);
    lookup.set(e.method, s);
  }
  return { scenarios, lookup };
}

function parseLog(logPath, patterns) {
  const order = [];
  const results = new Map();
  const contents = fs.readFileSync(logPath, "utf8");

  for (const raw of contents.split(/\r?\n/)) {
    const line = stripAnsi(raw).trim();
    if (!line) continue;

    const tm = line.match(patterns.testCase);
    if (tm) {
      const { method, status, duration } = tm.groups;
      let t = results.get(method);
      if (!t) { t = { method, status: "incomplete", durationSeconds: null, failureExcerpt: null }; results.set(method, t); order.push(method); }
      if (status !== "started") { t.status = status; if (duration) t.durationSeconds = parseFloat(duration); }
      continue;
    }

    const fm = line.match(patterns.failure);
    if (fm) {
      const { method, message } = fm.groups;
      let t = results.get(method);
      if (!t) { t = { method, status: "incomplete", durationSeconds: null, failureExcerpt: null }; results.set(method, t); order.push(method); }
      if (!t.failureExcerpt) t.failureExcerpt = message.trim();
    }
  }
  return { order, results };
}

function render(appLabel, artifactName, catalogScenarios, catalogLookup, order, results) {
  const lines = [`## ${appLabel} E2E Results`, ""];

  if (order.length === 0) {
    lines.push(`No test executions recorded. Full logs uploaded as \`${artifactName}\`.`);
    return lines.join("\n") + "\n";
  }

  const uncat = order.filter((m) => !catalogLookup.has(m));
  const ordered = [...catalogScenarios.map((s) => s.method).filter((m) => results.has(m)), ...uncat];
  const passed = ordered.filter((m) => results.get(m).status === "passed").length;
  const failed = ordered.filter((m) => results.get(m).status === "failed").length;
  const incomplete = ordered.filter((m) => results.get(m).status === "incomplete").length;

  lines.push(`${ordered.length} scenarios, ${passed} passed, ${failed} failed, ${incomplete} incomplete`);
  lines.push("", "| Status | Scenario | Duration | Description |", "| --- | --- | --- | --- |");

  for (const m of ordered) {
    const r = results.get(m);
    const s = catalogLookup.get(m) || { title: humanize(m), description: FALLBACK_DESCRIPTION };
    const icon = { passed: "✅ Passed", failed: "❌ Failed", incomplete: "⚠️ Incomplete" }[r.status];
    const dur = r.durationSeconds !== null ? `${r.durationSeconds.toFixed(1)}s` : "";
    lines.push(`| ${icon} | ${escapeCell(s.title)}<br><code>${escapeCell(m)}</code> | ${dur} | ${escapeCell(s.description)} |`);
  }

  const failing = ordered.filter((m) => { const s = results.get(m).status; return s === "failed" || s === "incomplete"; });
  if (failing.length > 0) {
    lines.push("", "### Failure Details");
    for (const m of failing) {
      const r = results.get(m);
      const s = catalogLookup.get(m) || { title: humanize(m) };
      const detail = r.failureExcerpt || "No failure excerpt found";
      lines.push(`- ${s.title} (\`${m}\`): ${detail}`);
    }
  }

  lines.push("", `Full logs uploaded as \`${artifactName}\`.`);
  return lines.join("\n") + "\n";
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  const testClass = opts["test-class"] || "DemoEmbeddedE2ETests";
  const appLabel = opts["app-label"] || "Demo Embedded";
  const artifactName = opts["artifact-name"] || "e2e-results";

  const patterns = buildPatterns(testClass);
  const { scenarios, lookup } = loadCatalog(opts.catalog);
  const parsed = fs.existsSync(opts.log) ? parseLog(opts.log, patterns) : { order: [], results: new Map() };
  const summary = render(appLabel, artifactName, scenarios, lookup, parsed.order, parsed.results);

  fs.mkdirSync(path.dirname(opts.summary), { recursive: true });
  fs.appendFileSync(opts.summary, summary, "utf8");
}

try { main(); } catch (e) { console.error(e instanceof Error ? e.message : String(e)); process.exitCode = 1; }
