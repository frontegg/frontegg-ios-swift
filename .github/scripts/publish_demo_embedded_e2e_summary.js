#!/usr/bin/env node

"use strict";

const fs = require("node:fs");
const path = require("node:path");

const TEST_CASE_PATTERN =
  /^Test Case '-\[[^ ]+\.DemoEmbeddedE2ETests (?<method>[^\]]+)]' (?<status>started|passed|failed)(?: \((?<duration>[0-9.]+) seconds\))?\.$/;
const FAILURE_PATTERN =
  /^.+error: -\[[^ ]+\.DemoEmbeddedE2ETests (?<method>[^\]]+)] : (?<message>.+)$/;
const ANSI_ESCAPE_PATTERN = /\x1b\[[0-9;]*m/g;
const FALLBACK_DESCRIPTION = "Description missing from scenario-catalog.json";
const TOKEN_PATTERN = /[A-Z]+(?=[A-Z][a-z]|[0-9]|$)|[A-Z]?[a-z]+|[0-9]+/g;
const TOKEN_OVERRIDES = {
  api: "API",
  id: "ID",
  idp: "IdP",
  oauth: "OAuth",
  oidc: "OIDC",
  saml: "SAML",
  sso: "SSO",
  ui: "UI",
  url: "URL",
};

function parseArgs(argv) {
  const options = {};

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (!argument.startsWith("--")) {
      throw new Error(`Unexpected argument: ${argument}`);
    }

    const key = argument.slice(2);
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) {
      throw new Error(`Missing value for --${key}`);
    }

    options[key] = value;
    index += 1;
  }

  for (const requiredKey of ["log", "catalog", "summary"]) {
    if (!options[requiredKey]) {
      throw new Error(`Missing required argument --${requiredKey}`);
    }
  }

  return options;
}

function stripAnsi(value) {
  return value.replace(ANSI_ESCAPE_PATTERN, "");
}

function escapeTableCell(value) {
  return String(value).replace(/\|/g, "\\|").replace(/\r?\n/g, " ").trim();
}

function titleizeToken(token) {
  const overridden = TOKEN_OVERRIDES[token.toLowerCase()];
  if (overridden) {
    return overridden;
  }

  return token.charAt(0).toUpperCase() + token.slice(1).toLowerCase();
}

function humanizeMethodName(method) {
  const withoutPrefix = method.startsWith("test") && method.length > 4 ? method.slice(4) : method;
  const tokens = withoutPrefix.match(TOKEN_PATTERN);
  if (!tokens) {
    return withoutPrefix;
  }

  return tokens.map(titleizeToken).join(" ");
}

function loadCatalog(catalogPath) {
  const payload = JSON.parse(fs.readFileSync(catalogPath, "utf8"));
  const rawTests = payload.tests;
  if (!Array.isArray(rawTests)) {
    throw new Error("Scenario catalog must contain a top-level 'tests' array");
  }

  const scenarios = [];
  const lookup = new Map();

  for (const entry of rawTests) {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      throw new Error("Each scenario catalog entry must be an object");
    }

    const { method, title, description } = entry;
    if (typeof method !== "string" || method.length === 0) {
      throw new Error("Each scenario catalog entry must include a non-empty 'method'");
    }
    if (typeof title !== "string" || title.length === 0) {
      throw new Error(`Scenario '${method}' must include a non-empty 'title'`);
    }
    if (typeof description !== "string" || description.length === 0) {
      throw new Error(`Scenario '${method}' must include a non-empty 'description'`);
    }
    if (lookup.has(method)) {
      throw new Error(`Duplicate scenario catalog entry for method '${method}'`);
    }

    const scenario = { method, title, description };
    scenarios.push(scenario);
    lookup.set(method, scenario);
  }

  return { scenarios, lookup };
}

function getOrCreateExecutedTest(results, executedOrder, method) {
  let test = results.get(method);
  if (!test) {
    test = {
      method,
      status: "incomplete",
      durationSeconds: null,
      failureExcerpt: null,
    };
    results.set(method, test);
    executedOrder.push(method);
  }

  return test;
}

function parseLog(logPath) {
  const executedOrder = [];
  const results = new Map();
  const contents = fs.readFileSync(logPath, "utf8");

  for (const rawLine of contents.split(/\r?\n/)) {
    const line = stripAnsi(rawLine).trim();
    if (!line) {
      continue;
    }

    const testMatch = line.match(TEST_CASE_PATTERN);
    if (testMatch) {
      const { method, status, duration } = testMatch.groups;
      const test = getOrCreateExecutedTest(results, executedOrder, method);

      if (status === "started") {
        continue;
      }

      test.status = status;
      if (duration) {
        test.durationSeconds = Number.parseFloat(duration);
      }
      continue;
    }

    const failureMatch = line.match(FAILURE_PATTERN);
    if (failureMatch) {
      const { method, message } = failureMatch.groups;
      const test = getOrCreateExecutedTest(results, executedOrder, method);
      if (test.failureExcerpt === null) {
        test.failureExcerpt = message.trim();
      }
    }
  }

  return { executedOrder, results };
}

function getScenario(catalogLookup, method) {
  return (
    catalogLookup.get(method) || {
      method,
      title: humanizeMethodName(method),
      description: FALLBACK_DESCRIPTION,
    }
  );
}

function formatDuration(durationSeconds) {
  return durationSeconds === null ? "" : `${durationSeconds.toFixed(1)}s`;
}

function renderSummary(catalogOrder, catalogLookup, executedOrder, results) {
  const lines = ["## Demo Embedded E2E Results", ""];

  if (executedOrder.length === 0) {
    lines.push("No `DemoEmbeddedE2ETests` executions were recorded in the xcodebuild log.");
    lines.push("");
    lines.push(
      "The run likely failed before test execution was recorded. Full logs and the result bundle are uploaded as the `demo-embedded-e2e-results` artifact."
    );
    return `${lines.join("\n")}\n`;
  }

  const uncataloguedMethods = executedOrder.filter((method) => !catalogLookup.has(method));
  const orderedMethods = [
    ...catalogOrder.map((scenario) => scenario.method).filter((method) => results.has(method)),
    ...uncataloguedMethods,
  ];

  const passedCount = orderedMethods.filter((method) => results.get(method).status === "passed").length;
  const failedCount = orderedMethods.filter((method) => results.get(method).status === "failed").length;
  const incompleteCount = orderedMethods.filter(
    (method) => results.get(method).status === "incomplete"
  ).length;

  lines.push(
    `${orderedMethods.length} scenarios, ${passedCount} passed, ${failedCount} failed, ${incompleteCount} incomplete`
  );
  lines.push("");
  lines.push("| Status | Scenario | Duration | Description |");
  lines.push("| --- | --- | --- | --- |");

  for (const method of orderedMethods) {
    const result = results.get(method);
    const scenario = getScenario(catalogLookup, method);
    const statusLabel = {
      passed: "✅ Passed",
      failed: "❌ Failed",
      incomplete: "⚠️ Incomplete",
    }[result.status];

    lines.push(
      `| ${statusLabel} | ${escapeTableCell(scenario.title)}<br><code>${escapeTableCell(
        method
      )}</code> | ${formatDuration(result.durationSeconds)} | ${escapeTableCell(
        scenario.description
      )} |`
    );
  }

  if (uncataloguedMethods.length > 0) {
    lines.push("");
    lines.push("### Catalog Warnings");
    for (const method of uncataloguedMethods) {
      lines.push(`- \`${method}\` is missing from \`demo-embedded/demo-embedded-e2e/scenario-catalog.json\`.`);
    }
  }

  const failingMethods = orderedMethods.filter((method) => {
    const status = results.get(method).status;
    return status === "failed" || status === "incomplete";
  });

  if (failingMethods.length > 0) {
    lines.push("");
    lines.push("### Failure Details");
    for (const method of failingMethods) {
      const result = results.get(method);
      const scenario = getScenario(catalogLookup, method);
      const detail =
        result.status === "incomplete"
          ? result.failureExcerpt || "No terminal result found in xcodebuild log"
          : result.failureExcerpt || "No XCTest failure excerpt found in xcodebuild log";
      lines.push(`- ${scenario.title} (\`${method}\`): ${detail}`);
    }
  }

  lines.push("");
  lines.push("Full logs and result bundle are uploaded as the `demo-embedded-e2e-results` artifact.");
  return `${lines.join("\n")}\n`;
}

function main() {
  const { log: logPath, catalog: catalogPath, summary: summaryPath } = parseArgs(process.argv.slice(2));
  const { scenarios, lookup } = loadCatalog(catalogPath);

  const parsed = fs.existsSync(logPath) ? parseLog(logPath) : { executedOrder: [], results: new Map() };
  const summary = renderSummary(scenarios, lookup, parsed.executedOrder, parsed.results);

  fs.mkdirSync(path.dirname(summaryPath), { recursive: true });
  fs.writeFileSync(summaryPath, summary, "utf8");
}

try {
  main();
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
