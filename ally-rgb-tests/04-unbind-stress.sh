#!/bin/bash
# 04-unbind-stress: bugs 1-3 regression test. Unbind/rebind the asus HID
# driver in a loop while a background writer hammers the LED sysfs files,
# racing asus_usb_rgb_zone_queue_update() against asus_usb_rgb_remove().
#
# Pre-fix kernels can oops here (delayed work re-armed after
# cancel_delayed_work_sync, firing on devm-freed memory ~30ms later).
# Post-fix the loop must survive; writes may fail with -ENODEV mid-unbind,
# which is expected and ignored. Run once on a CONFIG_KASAN=y build to
# make any lifetime regression unambiguous.
#
# Usage: 04-unbind-stress.sh [iterations]   (default 50)
set -u
cd "$(dirname "$0")" && . ./lib.sh
require_root
ITERS=${1:-50}
DRV=/sys/bus/hid/drivers/asus

devs=$(find_ally_hid_devs)
[ -n "$devs" ] || { fail "no Ally devices bound to $DRV"; summary; }
log "devices under test:"; echo "$devs" | sed 's/^/    /'

zones=$(require_zones)
for z in $zones; do
	save_zone_state "$z" "$RESULTS_DIR/$(basename "$z").state"
done

kmsg_mark

# background hammer: re-resolves zone paths every pass since they vanish
# and reappear across unbind/rebind; every write may legitimately fail.
hammer() {
	local i=0 z
	while [ -e "$RESULTS_DIR/.hammer_on" ]; do
		for z in $LEDS_GLOB; do
			[ -e "$z/brightness" ] || continue
			echo $((i % 101)) > "$z/brightness" 2>/dev/null
			echo "$((i%256)) 128 $(( 255 - i%256 ))" > "$z/multi_intensity" 2>/dev/null
		done
		i=$((i+1))
	done
}
touch "$RESULTS_DIR/.hammer_on"
hammer & HPID=$!
cleanup() {
	rm -f "$RESULTS_DIR/.hammer_on"
	wait "$HPID" 2>/dev/null
	# never leave the device unbound
	local d
	for d in $devs; do
		[ -e "$DRV/$d" ] || echo "$d" > "$DRV/bind" 2>/dev/null
	done
}
trap cleanup EXIT

it=1; oops=0
while [ "$it" -le "$ITERS" ]; do
	for d in $devs; do
		echo "$d" > "$DRV/unbind" 2>/dev/null
	done
	sleep 0.2
	for d in $devs; do
		echo "$d" > "$DRV/bind" 2>/dev/null
	done
	sleep 0.5
	if ! kmsg_since_mark | grep -Eq "$KMSG_FATAL_RE"; then
		[ $((it % 10)) -eq 0 ] && log "iteration $it/$ITERS ok"
	else
		oops=1
		fail "kernel corruption detected at iteration $it:"
		kmsg_since_mark | grep -E "$KMSG_FATAL_RE" -A 15 | head -60
		break
	fi
	it=$((it+1))
done

rm -f "$RESULTS_DIR/.hammer_on"; wait "$HPID" 2>/dev/null

[ "$oops" -eq 0 ] && pass "$ITERS unbind/rebind iterations with concurrent writes, no oops/UAF"

sleep 2   # let re-probe finish
zones_after=$(find_zones | wc -l)
zones_before=$(echo "$zones" | wc -l)
[ "$zones_after" -eq "$zones_before" ] \
	&& pass "all $zones_before zones re-registered after final rebind" \
	|| fail "zones after rebind: $zones_after != $zones_before"

if dmesg | tail -5 | grep -q "Created per-zone RGB controls"; then
	pass "driver logged RGB re-creation on rebind"
fi

kmsg_check_fatal
for z in $(find_zones); do
	restore_zone_state "$z" "$RESULTS_DIR/$(basename "$z").state"
done
summary
