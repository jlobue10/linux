#!/bin/bash
# 05-collect-logs: bundle everything needed to analyze a test run into a
# single tarball to attach to the PR / hand to another session.
set -u
cd "$(dirname "$0")" && . ./lib.sh
require_root

out="$RESULTS_DIR/collect.$(date +%Y%m%d-%H%M%S)"
mkdir -p "$out"

uname -a > "$out/uname.txt"
dmesg > "$out/dmesg.txt" 2>/dev/null
journalctl -k -b --no-pager > "$out/journal-kernel.txt" 2>/dev/null
cat /sys/class/dmi/id/board_name /sys/class/dmi/id/product_name \
	> "$out/dmi.txt" 2>/dev/null
command -v lsusb >/dev/null && lsusb > "$out/lsusb.txt" 2>&1
ls -l /sys/bus/hid/drivers/asus > "$out/hid-asus-bound.txt" 2>&1
[ -r /proc/config.gz ] && zgrep -E 'HID_ASUS|LEDS_CLASS|KASAN' /proc/config.gz \
	> "$out/config-relevant.txt"

for z in $(find_zones); do
	name=$(basename "$z")
	{
		echo "== $name =="
		for attr in zone supported_zones multi_intensity brightness \
			    max_brightness effect effect_index speed speed_range enabled; do
			printf '%-16s: %s\n' "$attr" "$(cat "$z/$attr" 2>/dev/null || echo '<unreadable>')"
		done
	} >> "$out/zones.txt"
done

# prior per-test state/result droppings, if any
cp -a "$RESULTS_DIR"/*.state "$out/" 2>/dev/null

tarball="$RESULTS_DIR/ally-rgb-logs-$(date +%Y%m%d-%H%M%S).tar.gz"
tar -C "$(dirname "$out")" -czf "$tarball" "$(basename "$out")"
log "collected -> $tarball"
pass "log bundle created"
summary
