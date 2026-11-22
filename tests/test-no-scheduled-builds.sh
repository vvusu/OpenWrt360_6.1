#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for workflow in \
    "$ROOT_DIR/.github/workflows/IPQ60XX-24.10(NOWIFI).yml" \
    "$ROOT_DIR/.github/workflows/IPQ60XX-ALL.yml"; do
    grep -F 'workflow_dispatch:' "$workflow" >/dev/null || {
        echo "FAIL: manual trigger missing from $workflow" >&2
        exit 1
    }

    if grep -E '^[[:space:]]*schedule:|^[[:space:]]*-[[:space:]]*cron:' "$workflow" >/dev/null; then
        echo "FAIL: scheduled firmware build still enabled in $workflow" >&2
        exit 1
    fi
done

echo "PASS: firmware builds are manual-only"
