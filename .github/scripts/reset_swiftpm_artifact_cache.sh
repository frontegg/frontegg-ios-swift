#!/usr/bin/env bash
set -euo pipefail

artifact_cache_dir="${HOME}/Library/Caches/org.swift.swiftpm/artifacts"

if [ -d "${artifact_cache_dir}" ]; then
  rm -rf "${artifact_cache_dir}"
fi
