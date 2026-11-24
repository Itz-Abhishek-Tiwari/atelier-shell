#!/usr/bin/env bash
# AdGuard DNS (ad/tracker blocking) on every saved Wi-Fi and wired connection, via NetworkManager.
#   adguard-dns.sh on       use AdGuard DNS (ignore the DNS the router hands out)
#   adguard-dns.sh family   AdGuard Family (also blocks adult content, forces safe search)
#   adguard-dns.sh off      back to the network's own DNS
#   adguard-dns.sh status   on | family | off
set -euo pipefail

V4_DEFAULT="94.140.14.14 94.140.15.15"
V6_DEFAULT="2a10:50c0::ad1:ff 2a10:50c0::ad2:ff"
V4_FAMILY="94.140.14.15 94.140.15.16"
V6_FAMILY="2a10:50c0::bad1:ff 2a10:50c0::bad2:ff"

connections() {
    nmcli -t -f UUID,TYPE connection show | awk -F: '$2 ~ /wireless|ethernet/ {print $1}'
}

status() {
    local dns
    dns=$(nmcli -g ipv4.dns connection show "$(nmcli -t -f UUID,DEVICE connection show --active | awk -F: '$2 != "lo" && $2 != "" {print $1; exit}')" 2>/dev/null || true)
    case "$dns" in
        *94.140.14.15*) echo family ;;
        *94.140.14.14*) echo on ;;
        *) echo off ;;
    esac
}

set_all() {   # $1 = v4 list, $2 = v6 list ("" = network default)
    local ignore=yes
    [ -z "$1" ] && ignore=no
    for u in $(connections); do
        nmcli connection modify "$u" \
            ipv4.dns "$1" ipv4.ignore-auto-dns "$ignore" \
            ipv6.dns "$2" ipv6.ignore-auto-dns "$ignore"
    done
    # re-apply on the active devices so it takes effect now (no reconnect)
    nmcli -t -f DEVICE,TYPE device status | awk -F: '$2 ~ /wifi|ethernet/ {print $1}' | while read -r dev; do
        nmcli device reapply "$dev" >/dev/null 2>&1 || true
    done
}

case "${1:-status}" in
    on)     set_all "$V4_DEFAULT" "$V6_DEFAULT"; status ;;
    family) set_all "$V4_FAMILY" "$V6_FAMILY"; status ;;
    off)    set_all "" ""; status ;;
    status) status ;;
    *) echo "usage: $0 on|family|off|status" >&2; exit 2 ;;
esac
