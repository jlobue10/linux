#!/bin/bash
# 00-env-check: verify the device, kernel, and driver are ready for the
# RGB tests. Read-only; safe to run any time.
set -u
cd "$(dirname "$0")" && . ./lib.sh
require_root

log "kernel: $(uname -r)"

board=$(cat /sys/class/dmi/id/board_name 2>/dev/null || echo unknown)
product=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown)
log "DMI board: $board, product: $product"
case "$board$product" in
	*RC73YA*|*RC73XA*|*RC71*|*RC72*) pass "recognized ROG Ally-family hardware" ;;
	*) warn "not an Ally-family board by DMI; RGB zones may not exist here" ;;
esac

if [ -r /proc/config.gz ]; then
	for opt in CONFIG_HID_ASUS CONFIG_LEDS_CLASS_MULTICOLOR; do
		if zgrep -qE "^$opt=[ym]" /proc/config.gz; then
			pass "$opt enabled"
		else
			fail "$opt not enabled in running kernel"
		fi
	done
else
	warn "/proc/config.gz unavailable (CONFIG_IKCONFIG_PROC); skipping config check"
fi

devs=$(find_ally_hid_devs)
if [ -n "$devs" ]; then
	pass "hid-asus bound to Ally device(s):"
	echo "$devs" | sed 's/^/    /'
else
	fail "no Ally device (0b05:1abe/0b05:1b4c) bound to the asus HID driver"
fi

if dmesg | grep -q "Created per-zone RGB controls"; then
	pass "driver logged 'Created per-zone RGB controls'"
else
	warn "'Created per-zone RGB controls' not in dmesg (may have rotated out)"
fi

zones=$(find_zones)
if [ -n "$zones" ]; then
	pass "RGB zones present:"
	for z in $zones; do
		echo "    $(basename "$z"): brightness=$(cat "$z/brightness")/$(cat "$z/max_brightness")" \
		     "multi_intensity='$(cat "$z/multi_intensity")'" \
		     "effect=$(cat "$z/effect" 2>/dev/null || echo n/a)"
	done
	for z in $zones; do
		for attr in multi_intensity brightness effect effect_index speed speed_range enabled zone; do
			[ -e "$z/$attr" ] || warn "$(basename "$z") missing attribute: $attr"
		done
	done
else
	fail "no asus:rgb:key* LED class devices found"
fi

summary
