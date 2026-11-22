#!/usr/bin/env bash
# wifi-connect.sh <ssid>
# Connects to a Wi-Fi network for the Wi-Fi drawer (WifiOverlay.qml).
# The password (may be empty) is read from the first line of stdin, so it is
# never pasted into a shell string: quotes, $, ` and \ in it stay intact.
# Prints exactly one result line:
#   OK
#   AUTH <message>   wrong or missing password (the drawer asks for one)
#   FAIL <message>   anything else (out of range, timeout, ...)
ssid="$1"
IFS= read -r pw || true
[ -n "$ssid" ] || { echo "FAIL no network given"; exit 2; }

has_profile() { nmcli connection show id "$ssid" >/dev/null 2>&1; }

if [ -n "$pw" ]; then
    if has_profile; then
        # A saved profile with an old/wrong password would keep failing with
        # "psk mismatch": replace the stored password, then bring it up.
        out=$(nmcli connection modify id "$ssid" wifi-sec.psk "$pw" 2>&1) &&
            out=$(nmcli -w 45 connection up id "$ssid" 2>&1)
    else
        out=$(nmcli -w 45 device wifi connect "$ssid" password "$pw" 2>&1)
    fi
else
    if has_profile; then
        out=$(nmcli -w 45 connection up id "$ssid" 2>&1)
    else
        out=$(nmcli -w 45 device wifi connect "$ssid" 2>&1)
    fi
fi
rc=$?

if [ $rc -eq 0 ]; then
    echo "OK"
    exit 0
fi

msg=$(printf '%s' "$out" | grep -v '^\s*$' | tail -n 1 | sed 's/^Error: //')
if printf '%s' "$out" | grep -qiE 'secrets were required|no secrets|psk|password|802-11-wireless-security|key-mgmt'; then
    echo "AUTH ${msg:-wrong password}"
else
    echo "FAIL ${msg:-could not connect}"
fi
exit 1
