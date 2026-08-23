#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/IPQ60XX-6.6-WIFI(EMMC).yml"
CONFIG="$ROOT_DIR/configs/ipq60xx-6.6-wifi(emmc).config"

if grep -F 'docker rmi $(docker images -q)' "$WORKFLOW" >/dev/null; then
    echo "FAIL: empty Docker image list invokes docker rmi without arguments" >&2
    exit 1
fi

grep -F 'while IFS= read -r image; do' "$WORKFLOW" >/dev/null || {
    echo "FAIL: missing empty-safe Docker image cleanup" >&2
    exit 1
}

grep -F 'REPO_COMMIT: bfe94963ec1933333cdd09d09a6fa3d335aebf60' "$WORKFLOW" >/dev/null || {
    echo "FAIL: 6.6 workflow is not pinned to the last 6.6 source commit" >&2
    exit 1
}

grep -F 'CONFIG_TARGET_qualcommax_ipq60xx_DEVICE_jdcloud_re-ss-01=y' "$CONFIG" >/dev/null || {
    echo "FAIL: 6.6 config does not select JDCloud RE-SS-01" >&2
    exit 1
}

echo "PASS: IPQ60XX 6.6 EMMC workflow handles an empty Docker image list"
