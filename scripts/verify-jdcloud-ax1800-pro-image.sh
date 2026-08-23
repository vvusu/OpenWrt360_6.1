#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="${1:-}"
MAX_FACTORY_SIZE_BYTES=62914560
PROFILE_TOKEN="jdcloud_re-ss-01"
FACTORY_SUFFIX="jdcloud_re-ss-01-squashfs-factory.bin"
SYSUPGRADE_SUFFIX="jdcloud_re-ss-01-squashfs-sysupgrade.bin"

if [[ -z "$BIN_DIR" || ! -d "$BIN_DIR" ]]; then
    echo "Usage: $0 <bin-directory>" >&2
    exit 2
fi

factories=()
while IFS= read -r image; do
    factories+=("$image")
done < <(find "$BIN_DIR" -type f -name "*${FACTORY_SUFFIX}" -print)

sysupgrades=()
while IFS= read -r image; do
    sysupgrades+=("$image")
done < <(find "$BIN_DIR" -type f -name "*${SYSUPGRADE_SUFFIX}" -print)

[[ "${#factories[@]}" -eq 1 ]] || {
    echo "ERROR: expected exactly one ${PROFILE_TOKEN} factory.bin, found ${#factories[@]}" >&2
    exit 1
}
[[ "${#sysupgrades[@]}" -eq 1 ]] || {
    echo "ERROR: expected exactly one ${PROFILE_TOKEN} sysupgrade.bin, found ${#sysupgrades[@]}" >&2
    exit 1
}

file_size() {
    stat -c %s "$1" 2>/dev/null || stat -f %z "$1"
}

factory="${factories[0]}"
sysupgrade="${sysupgrades[0]}"
factory_size="$(file_size "$factory")"

echo "=== JDCloud AX1800 Pro artifacts ==="
sha256sum "$factory" "$sysupgrade" 2>/dev/null || shasum -a 256 "$factory" "$sysupgrade"

if (( factory_size > MAX_FACTORY_SIZE_BYTES )); then
    echo "ERROR: factory.bin is ${factory_size} bytes, above the 60 MiB partition limit" >&2
    exit 1
fi

echo "PASS: factory.bin is ${factory_size} bytes (limit ${MAX_FACTORY_SIZE_BYTES})"
