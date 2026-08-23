#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/IPQ60XX-6.12-WIFI(EMMC).yml"
CONFIG="$ROOT_DIR/configs/ipq60xx-6.12-wifi-emmc.config"

test -f "$WORKFLOW" || {
    echo "FAIL: missing IPQ60XX 6.12 Wi-Fi EMMC workflow" >&2
    exit 1
}

for expected in \
    'SOURCE_BRANCH: main-nss' \
    'SOURCE_COMMIT: df3fe8169fc0d63afea13c69d83bae21c92b3300' \
    'CONFIG_FILE: configs/ipq60xx-6.12-wifi-emmc.config' \
    'KERNEL_PATCHVER:=6.12' \
    'verify-jdcloud-ax1800-pro-image.sh'; do
    grep -F "$expected" "$WORKFLOW" >/dev/null || {
        echo "FAIL: 6.12 workflow is missing: $expected" >&2
        exit 1
    }
done

test -f "$CONFIG" || {
    echo "FAIL: missing dedicated IPQ60XX 6.12 EMMC config" >&2
    exit 1
}

grep -F 'CONFIG_TARGET_qualcommax_ipq60xx_DEVICE_jdcloud_re-ss-01=y' "$CONFIG" >/dev/null || {
    echo "FAIL: 6.12 config does not use the accepted JDCloud device symbol" >&2
    exit 1
}

if grep -F 'CONFIG_TARGET_DEVICE_qualcommax_ipq60xx_DEVICE_jdcloud_re-ss-01=y' "$CONFIG" >/dev/null; then
    echo "FAIL: 6.12 config still contains the rejected 25.12 device symbol" >&2
    exit 1
fi

grep -F "grep -q '^CONFIG_TARGET_qualcommax_ipq60xx_DEVICE_jdcloud_re-ss-01=y$' .config" "$WORKFLOW" >/dev/null || {
    echo "FAIL: device validation does not require the actual 6.12 target symbol" >&2
    exit 1
}

grep -F "Missing package after make defconfig:" "$WORKFLOW" >/dev/null || {
    echo "FAIL: package validation does not report the missing package" >&2
    exit 1
}

if grep -F 'docker rmi $(docker images -q)' "$WORKFLOW" >/dev/null; then
    echo "FAIL: empty Docker image list invokes docker rmi without arguments" >&2
    exit 1
fi

disk_line="$(grep -n -- '- name: Free disk space' "$WORKFLOW" | cut -d: -f1)"
checkout_line="$(grep -n -- '- name: Checkout build configuration' "$WORKFLOW" | cut -d: -f1)"
[[ "$disk_line" -lt "$checkout_line" ]] || {
    echo "FAIL: repository checkout must happen after runner disk remount" >&2
    exit 1
}

echo "PASS: IPQ60XX 6.12 Wi-Fi EMMC workflow is pinned and guarded"
