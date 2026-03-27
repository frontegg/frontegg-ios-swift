#!/usr/bin/env node

"use strict";

const fs = require("node:fs");

const APP_CONFIGS = {
  embedded: {
    project: "demo-embedded/demo-embedded.xcodeproj",
    scheme: "demo-embedded",
    testTarget: "demo-embedded-e2e",
    testClass: "DemoEmbeddedE2ETests",
    catalog: "demo-embedded/demo-embedded-e2e/scenario-catalog.json",
  },
  "multi-region": {
    project: "demo-multi-region/demo-multi-region.xcodeproj",
    scheme: "demo-multi-region",
    testTarget: "demo-multi-region-e2e",
    testClass: "MultiRegionE2ETests",
    catalog: "demo-multi-region/demo-multi-region-e2e/scenario-catalog.json",
  },
  uikit: {
    project: "demo-uikit/demo-uikit.xcodeproj",
    scheme: "demo-uikit",
    testTarget: "demo-uikit-e2e",
    testClass: "UIKitE2ETests",
    catalog: "demo-uikit/demo-uikit-e2e/scenario-catalog.json",
  },
};

function readTestMethods(catalogPath) {
  try {
    const raw = JSON.parse(fs.readFileSync(catalogPath, "utf-8"));
    const entries = raw.tests || raw.scenarios || [];
    return entries.map((e) => e.method);
  } catch {
    return [];
  }
}

function splitIntoShards(items, shardCount) {
  const shards = Array.from({ length: shardCount }, () => []);
  items.forEach((item, i) => shards[i % shardCount].push(item));
  return shards;
}

function main() {
  const appsInput = process.env.INPUT_APPS || "embedded,multi-region,uikit";
  const parsed = parseInt(process.env.INPUT_SHARD_COUNT || "1", 10);
  const shardCount = Number.isNaN(parsed) ? 1 : Math.max(1, parsed);

  const apps = appsInput
    .split(",")
    .map((s) => s.trim())
    .filter((s) => APP_CONFIGS[s]);

  const include = [];

  for (const app of apps) {
    const config = APP_CONFIGS[app];
    const methods = readTestMethods(config.catalog);

    if (shardCount <= 1 || methods.length === 0) {
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
      const effectiveShards = Math.min(shardCount, methods.length);
      const shards = splitIntoShards(methods, effectiveShards);

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
          "shard-total": effectiveShards,
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
