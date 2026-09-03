#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT_DIR/configs/jdcloud-ax1800-pro.config"
WORKFLOW="$ROOT_DIR/.github/workflows/JDCLOUD-AX1800-PRO.yml"
VERIFIER="$ROOT_DIR/scripts/verify-jdcloud-ax1800-pro-image.sh"
HOMEPROXY_DEFAULT="$ROOT_DIR/files/etc/config/homeproxy"
HOMEPROXY_GUARD="$ROOT_DIR/scripts/fix-homeproxy-config.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_contains() {
    local file="$1"
    local text="$2"
    grep -F -- "$text" "$file" >/dev/null || fail "$file is missing: $text"
}

test -f "$CONFIG" || fail "missing dedicated JDCloud config"
test -f "$WORKFLOW" || fail "missing dedicated JDCloud workflow"
test -x "$VERIFIER" || fail "missing executable image verifier"
test -s "$HOMEPROXY_DEFAULT" || fail "missing/empty homeproxy default config"
test -s "$HOMEPROXY_GUARD" || fail "missing homeproxy uci-defaults guard"
assert_contains "$HOMEPROXY_DEFAULT" "config homeproxy 'infra'"
assert_contains "$HOMEPROXY_GUARD" '/rom/etc/config/homeproxy'
assert_contains "$WORKFLOW" 'files/etc/config/homeproxy" files/etc/config/'
assert_contains "$WORKFLOW" 'fix-homeproxy-config.sh" files/etc/uci-defaults/98-fix-homeproxy-config'

assert_contains "$CONFIG" 'CONFIG_TARGET_qualcommax_ipq60xx_DEVICE_jdcloud_re-ss-01=y'
assert_contains "$CONFIG" 'CONFIG_TARGET_DEVICE_PACKAGES_qualcommax_ipq60xx_DEVICE_jdcloud_re-ss-01="ipq-wifi-jdcloud_re-ss-01"'

if grep -F 'CONFIG_TARGET_DEVICE_qualcommax_ipq60xx_DEVICE_jdcloud_re-ss-01=y' "$CONFIG" >/dev/null; then
    fail "dedicated config still uses the rejected 25.12 device symbol"
fi

device_count="$(grep -Ec '^CONFIG_TARGET_(DEVICE_)?[^_]+_[^_]+_DEVICE_.*=y$' "$CONFIG")"
[[ "$device_count" == "1" ]] || fail "dedicated config selects $device_count devices"

for package in \
    luci-app-homeproxy sing-box luci-app-mosdns luci-app-tailscale \
    luci-app-ddns-go luci-app-ttyd openssh-sftp-server \
    luci-app-wol luci-app-watchcat luci-app-irqbalance \
    luci-app-nlbwmon luci-app-filemanager luci-app-upnp \
    luci-app-sqm luci-app-ksmbd block-mount kmod-fs-ext4 \
    htop ethtool luci-app-store xz-utils; do
    assert_contains "$CONFIG" "CONFIG_PACKAGE_${package}=y"
done

for package in luci-app-openclash luci-app-passwall luci-app-mihomo \
    mihomo adguardhome luci-app-adguardhome docker dockerd; do
    if grep -F "CONFIG_PACKAGE_${package}=y" "$CONFIG" >/dev/null; then
        fail "dedicated config must exclude $package"
    fi
done

assert_contains "$WORKFLOW" 'SOURCE_BRANCH: 25.12-nss'
assert_contains "$WORKFLOW" 'MOSDNS_COMMIT: b230ca12cba16aab2c163452bfd76f1631e2a537'
assert_contains "$WORKFLOW" 'TAILSCALE_LUCI_COMMIT: 534eb3f3acba24dac4e6fee9fa33049b004ef121'
assert_contains "$WORKFLOW" 'ISTORE_COMMIT: 3fca15b30aeed9ecacb3efc8b4a8b9c2584ad5c7'
assert_contains "$WORKFLOW" 'https://github.com/linkease/istore.git'
assert_contains "$WORKFLOW" 'for pkg in luci-app-store luci-lib-taskd luci-lib-xterm taskd; do'
assert_contains "$WORKFLOW" 'istore/luci/$pkg" package/community/'

dependency_line="$(grep -n -- '- name: Install build dependencies' "$WORKFLOW" | cut -d: -f1)"
disk_line="$(grep -n -- '- name: Free disk space' "$WORKFLOW" | cut -d: -f1)"
checkout_line="$(grep -n -- '- name: Checkout build configuration' "$WORKFLOW" | cut -d: -f1)"
[[ "$dependency_line" -lt "$disk_line" ]] || \
    fail "build dependencies must be installed before repartitioning runner disk space"
[[ "$disk_line" -lt "$checkout_line" ]] || \
    fail "repository checkout must happen after runner disk remount"
assert_contains "$WORKFLOW" 'CONFIG_FILE: configs/jdcloud-ax1800-pro.config'
assert_contains "$WORKFLOW" "grep -q '^CONFIG_TARGET_qualcommax_ipq60xx_DEVICE_jdcloud_re-ss-01=y$' .config"
assert_contains "$WORKFLOW" 'JDCloud RE-SS-01 target was not selected after make defconfig'
assert_contains "$WORKFLOW" 'verify-jdcloud-ax1800-pro-image.sh'
assert_contains "$VERIFIER" 'MAX_FACTORY_SIZE_BYTES=62914560'
assert_contains "$VERIFIER" 'jdcloud_re-ss-01-squashfs-factory.bin'

for duplicate in \
    'package/community/luci-app-tailscale/root/etc/config/tailscale' \
    'package/community/luci-app-tailscale/root/etc/init.d/tailscale'; do
    assert_contains "$WORKFLOW" "rm -f $duplicate"
done

# CI hygiene: current actions majors and source download cache.
assert_contains "$WORKFLOW" 'actions/checkout@v7'
assert_contains "$WORKFLOW" 'actions/upload-artifact@v7'
assert_contains "$WORKFLOW" 'actions/cache@v6'
assert_contains "$WORKFLOW" 'retention-days: 90'
if grep -Fq 'actions/checkout@v4' "$WORKFLOW" || grep -Fq 'actions/upload-artifact@v4' "$WORKFLOW"; then
    fail "workflow still pins deprecated Node 20 action majors"
fi
assert_contains "$WORKFLOW" 'path: openwrt/dl'

fixture="$(mktemp -d "${TMPDIR:-/tmp}/jdcloud-old-image-test.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
truncate -s 1048576 "$fixture/libwrt-qualcommax-ipq60xx-jdcloud_re-ss-01-squashfs-factory.bin"
truncate -s 2097152 "$fixture/libwrt-qualcommax-ipq60xx-jdcloud_re-ss-01-squashfs-sysupgrade.bin"
bash "$VERIFIER" "$fixture" >/dev/null

truncate -s 62914561 "$fixture/libwrt-qualcommax-ipq60xx-jdcloud_re-ss-01-squashfs-factory.bin"
if bash "$VERIFIER" "$fixture" >/dev/null 2>&1; then
    fail "verifier accepted an oversized factory image"
fi

echo "PASS: dedicated JDCloud AX1800 Pro build configuration"
