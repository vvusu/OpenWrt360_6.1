#!/bin/sh
# NSS stability hardening (JDCloud AX1800 Pro / qualcommax NSS builds).
#
# Lessons from the 2026-09-03 incident:
#   1. homeproxy starts sing-box before WAN is up -> remote rule-set download
#      FATALs -> procd respawn storm (bare `respawn` = infinite retries)
#      chokes the whole system at boot.
#   2. proxy_mode `redirect_tproxy` (UDP tproxy) x NSS/ECM acceleration can
#      hang the kernel -> silent watchdog reset with no logs. The baked
#      default config now uses `redirect` (TCP-only); users can still opt
#      back into tproxy from LuCI.
#   3. Silent hangs leave no evidence -> persistent syslog black box.
#
# This script is defensive by design: every change checks for its marker
# first and silently skips if the upstream layout has changed.

INIT="/etc/init.d/homeproxy"

hp_log() { logger -t nss-stability -s "$*"; }

# --- 1) Cap procd respawn retries (bare respawn = infinite) ----------------
if [ -f "$INIT" ] && grep -q 'procd_set_param respawn$' "$INIT"; then
	sed -i 's/^\([[:space:]]*\)procd_set_param respawn$/\1procd_set_param respawn 3600 5 5/' "$INIT"
	hp_log "capped homeproxy respawn retries (3600 5 5)"
fi

# --- 2) WAN-wait gate before the client instance starts --------------------
if [ -f "$INIT" ] && grep -q '"$outbound_node" != "nil"' "$INIT" \
	&& ! grep -q 'deferring client start' "$INIT"; then
	awk '
		!done && /^[[:space:]]*if \[ "\$outbound_node" != "nil" \]; then[[:space:]]*$/ {
			print
			print "\t\t# NSS-stability: remote rule-sets need internet at start."
			print "\t\t# If offline, bail out -- the procd interface trigger"
			print "\t\t# reloads this service when WAN comes up (no crash loop)."
			print "\t\tlocal wan_wait=0"
			print "\t\twhile [ \"\$wan_wait\" -lt 30 ] && ! ip route get 223.5.5.5 >/dev/null 2>&1; do"
			print "\t\t\twan_wait=\$((wan_wait+2))"
			print "\t\t\tsleep 2"
			print "\t\tdone"
			print "\t\tif ! ip route get 223.5.5.5 >/dev/null 2>&1; then"
			print "\t\t\tlog \"No internet after \${wan_wait}s, deferring client start until WAN is up.\""
			print "\t\t\treturn 1"
			print "\t\tfi"
			print ""
			print "\t\t# Settle delay: avoid the WAN-up activation storm. Firewall reload,"
			print "\t\t# ECM first flows, tailscale rebind and mosdns restart all land within"
			print "\t\t# ~25s of ifup; injecting sing-box NAT rules into that window froze"
			print "\t\t# the kernel for ~5 minutes (2026-09-04 incident). Back off 75s and"
			print "\t\t# re-verify the route afterwards."
			print "\t\tsleep 75"
			print "\t\tif ! ip route get 223.5.5.5 >/dev/null 2>&1; then"
			print "\t\t\tlog \"WAN lost during settle delay; deferring client start until WAN is up.\""
			print "\t\t\treturn 1"
			print "\t\tfi"
			done = 1
			next
		}
		{ print }
	' "$INIT" > "${INIT}.tmp" && cat "${INIT}.tmp" > "$INIT" && rm -f "${INIT}.tmp"
	hp_log "installed WAN-wait gate in homeproxy init"
fi

# --- 4) Persistent syslog black box (survives reboots) ---------------------
mkdir -p /log
if [ "$(uci -q get system.@system[0].log_file)" != "/log/system.log" ]; then
	uci -q set system.@system[0].log_file='/log/system.log'
	uci -q set system.@system[0].log_size='512'
	uci commit system
	hp_log "persistent syslog -> /log/system.log (512KB ring)"
fi

exit 0
