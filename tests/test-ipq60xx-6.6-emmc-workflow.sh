#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/IPQ60XX-6.6-WIFI(EMMC).yml"

if grep -F 'docker rmi $(docker images -q)' "$WORKFLOW" >/dev/null; then
    echo "FAIL: empty Docker image list invokes docker rmi without arguments" >&2
    exit 1
fi

grep -F 'while IFS= read -r image; do' "$WORKFLOW" >/dev/null || {
    echo "FAIL: missing empty-safe Docker image cleanup" >&2
    exit 1
}

echo "PASS: IPQ60XX 6.6 EMMC workflow handles an empty Docker image list"
