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

if grep -F '0001-show-soc-status-on-luci.patch' "$WORKFLOW" >/dev/null; then
    echo "FAIL: workflow applies an obsolete LuCI status patch" >&2
    exit 1
fi

for pin in \
    'NSS_PACKAGES_COMMIT: 061e717e065edfecd939a98510334b356064a079' \
    'SQM_NSS_COMMIT: 4b4ed8639229be5e70cf94b73cdf7dbc09e66d5d' \
    'PACKAGES_COMMIT: 0d18846dab8aba7a2c7a0ad3feeae42660fac36f' \
    'LUCI_COMMIT: 74eef5c7d99c46c3d5cfcd4be847feef53467c85' \
    'ROUTING_COMMIT: 9eda32a8c96fc184e6b208a54dbf43a1379fa0be' \
    'TELEPHONY_COMMIT: 70d6a028ab7ba209c232987c2126291e0903c242' \
    'VIDEO_COMMIT: 2ebf064c0583f031dc41e4c1bf4f404bbcd3f3c7'; do
    grep -F "$pin" "$WORKFLOW" >/dev/null || {
        echo "FAIL: 6.6 workflow is missing feed pin: $pin" >&2
        exit 1
    }
done

grep -F -- '- name: Pin feeds to 6.6-compatible revisions' "$WORKFLOW" >/dev/null || {
    echo "FAIL: 6.6 workflow does not rewrite feeds to pinned revisions" >&2
    exit 1
}

if grep -F '*.ipk' "$WORKFLOW" >/dev/null; then
    echo "FAIL: 6.6 artifact collection still assumes the removed OPKG/IPK format" >&2
    exit 1
fi

grep -F -- "-name '*.apk'" "$WORKFLOW" >/dev/null || {
    echo "FAIL: 6.6 artifact collection does not collect APK packages" >&2
    exit 1
}

echo "PASS: IPQ60XX 6.6 EMMC workflow handles an empty Docker image list"
