#!/bin/sh
# Guard against the homeproxy conffile shipping empty: if the active
# /etc/config/homeproxy is missing or 0 bytes (e.g. kept from an older
# sysupgrade backup), restore the default that is baked into ROM via
# the build-time files/ overlay.
[ -s /etc/config/homeproxy ] || cp /rom/etc/config/homeproxy /etc/config/homeproxy
exit 0
