#!/usr/bin/env node

"use strict";

const fs = require("node:fs");

const MAX_TESTS_PER_SHARD = 4;

const APP_CONFIGS = {
  embedded: {
    project: "demo-embedded/demo-embedded.xcodeproj",
    scheme: "demo-embedded",
    testTarget: "demo-embedded-e2e",
    testClass: "DemoEmbeddedE2ETests",
    catalog: "demo-embedded/demo-embedded-e2e/scenario-catalog.json",
    testSources: ["demo-embedded/demo-embedded-e2e/DemoEmbeddedE2ETests.swift"],
  },
  "multi-region": {
    project: "demo-multi-region/demo-multi-region.xcodeproj",
    scheme: "demo-multi-region",
    testTarget: "demo-multi-region-e2e",
    testClass: "MultiRegionE2ETests",
    catalog: "demo-multi-region/demo-multi-region-e2e/scenario-catalog.json",
    testSources: ["demo-multi-region/demo-multi-region-e2e/MultiRegionE2ETests.swift"],
  },
  uikit: {
    project: "demo-uikit/demo-uikit.xcodeproj",
    scheme: "demo-uikit",
    testTarget: "demo-uikit-e2e",
    testClass: "UIKitE2ETests",
    catalog: "demo-uikit/demo-uikit-e2e/scenario-catalog.json",
    testSources: ["demo-uikit/demo-uikit-e2e/UIKitE2ETests.swift"],
  },
  "auto-login": {
    project: "demo-auto-login/demo-auto-login.xcodeproj",
    scheme: "demo-auto-login",
    testTarget: "demo-auto-login-e2e",
    testClass: "AutoLoginE2ETests",
    catalog: "demo-auto-login/demo-auto-login-e2e/scenario-catalog.json",
    testSources: ["demo-auto-login/demo-auto-login-e2e/AutoLoginE2ETests.swift"],
  },
};

function readCatalogMethods(catalogPath) {
  const raw = JSON.parse(fs.readFileSync(catalogPath, "utf-8"));
  const entries = raw.tests || raw.scenarios || [];
  return entries
    .map((entry) => entry.method)
    .filter((method) => typeof method === "string" && method.length > 0);
}

function readSourceTestMethods(testSources) {
  const methods = new Set();
  const testMethodRegex = /^\s*func\s+(test[A-Za-z0-9_]+)\s*\(/gm;

  for (const sourcePath of testSources) {
    const source = fs.readFileSync(sourcePath, "utf-8");
    for (const match of source.matchAll(testMethodRegex)) {
      methods.add(match[1]);
    }
  }

  return [...methods];
}

function validateCatalog(app, catalogMethods, sourceMethods) {
  const catalogSet = new Set(catalogMethods);
  const sourceSet = new Set(sourceMethods);

  const catalogOnly = catalogMethods.filter((method) => !sourceSet.has(method));
  const sourceOnly = sourceMethods.filter((method) => !catalogSet.has(method));

  if (catalogOnly.length === 0 && sourceOnly.length === 0) {
    return;
  }

  const problems = [];
  if (catalogOnly.length > 0) {
    problems.push(`catalog-only methods: ${catalogOnly.join(", ")}`);
  }
  if (sourceOnly.length > 0) {
    problems.push(`uncatalogued source methods: ${sourceOnly.join(", ")}`);
  }

  throw new Error(`Scenario catalog drift detected for ${app}: ${problems.join("; ")}`);
}

function splitIntoShards(items, shardCount) {
  const shards = Array.from({ length: shardCount }, () => []);
  items.forEach((item, i) => shards[i % shardCount].push(item));
  return shards;
}

function main() {
  const appsInput = process.env.INPUT_APPS || "embedded,multi-region,uikit,auto-login";
  const parsed = parseInt(process.env.INPUT_SHARD_COUNT || "1", 10);
  const shardCount = Number.isNaN(parsed) ? 1 : Math.max(1, parsed);

  const apps = appsInput
    .split(",")
    .map((s) => s.trim())
    .filter((s) => APP_CONFIGS[s]);

  const include = [];

  for (const app of apps) {
    const config = APP_CONFIGS[app];
    const methods = readCatalogMethods(config.catalog);
    const sourceMethods = readSourceTestMethods(config.testSources || []);

    validateCatalog(app, methods, sourceMethods);

    // Determine effective shard count:
    // - If explicit shard_count > 1, use it
    // - Otherwise, auto-shard so each shard has at most MAX_TESTS_PER_SHARD tests
    const autoShards = Math.ceil(methods.length / MAX_TESTS_PER_SHARD);
    const effectiveShardCount = shardCount > 1
      ? Math.min(shardCount, methods.length || 1)
      : Math.max(1, autoShards);

    if (effectiveShardCount <= 1 || methods.length === 0) {
      include.push({
        app,
        project: config.project,
        scheme: config.scheme,
        "test-target": config.testTarget,
        "test-class": config.testClass,
        catalog: config.catalog,
        "shard-index": 1,
        "shard-total": 1,
        "only-testing": "",
      });
    } else {
      const shards = splitIntoShards(methods, effectiveShardCount);

      shards.forEach((shard, i) => {
        const onlyTesting = shard
          .map((m) => `-only-testing:${config.testTarget}/${config.testClass}/${m}`)
          .join(" ");

        include.push({
          app,
          project: config.project,
          scheme: config.scheme,
          "test-target": config.testTarget,
          "test-class": config.testClass,
          catalog: config.catalog,
          "shard-index": i + 1,
          "shard-total": effectiveShardCount,
          "only-testing": onlyTesting,
        });
      });
    }
  }

  const matrix = JSON.stringify({ include });
  const outputFile = process.env.GITHUB_OUTPUT;
  if (outputFile) {
    fs.appendFileSync(outputFile, `matrix=${matrix}\n`);
  }
  console.log(matrix);
}

main();
