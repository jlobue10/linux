#!/bin/bash
# 03-suspend-resume: bug-4 regression test. A color written inside the
# 30ms debounce window right before suspend must survive the
# suspend->commit (0xb4) path and still be on the LEDs after resume.
# Pre-fix kernels cancel the pending work and the color reverts.
#
# ACTUALLY SUSPENDS THE DEVICE (rtcwake, ~20s per cycle). Run from a
# local console, not over a network session that dies on suspend.
#
# Usage: 03-suspend-resume.sh [cycles]   (default 3)
# Set MCU_POWERSAVE=1 to also flip mcu_powersave on first, forcing the
# USB re-enumeration / reset_resume path on Ally hardware.
set -u
cd "$(dirname "$0")" && . ./lib.sh
require_root
CYCLES=${1:-3}

command -v rtcwake >/dev/null || { fail "rtcwake not installed"; summary; }

zones=$(require_zones)
z1=$(echo "$zones" | head -1)
st="$RESULTS_DIR/$(basename "$z1").state"
save_zone_state "$z1" "$st"

find_mcu_powersave() {
	local p
	for p in /sys/devices/platform/asus-nb-wmi/mcu_powersave \
		 /sys/class/firmware-attributes/*/attributes/mcu_powersave/current_value \
		 /sys/bus/platform/drivers/asus-armoury/*/mcu_powersave; do
		[ -w "$p" ] && { echo "$p"; return; }
	done
}

if [ "${MCU_POWERSAVE:-0}" = 1 ]; then
	mp=$(find_mcu_powersave)
	if [ -n "${mp:-}" ]; then
		old_mp=$(cat "$mp")
		echo 1 > "$mp" && log "mcu_powersave=1 via $mp (was $old_mp)"
		trap 'echo "$old_mp" > "$mp" 2>/dev/null' EXIT
	else
		warn "mcu_powersave knob not found; running plain s2idle cycles"
	fi
fi

kmsg_mark
cycle=1
while [ "$cycle" -le "$CYCLES" ]; do
	# distinct color per cycle so a stale commit is visually obvious
	case $((cycle % 3)) in
		1) rgbv="255 0 255"; label=magenta ;;
		2) rgbv="255 128 0"; label=orange ;;
		0) rgbv="0 255 255"; label=cyan ;;
	esac
	log "cycle $cycle/$CYCLES: static $label, then immediate suspend"
	echo static > "$z1/effect"
	echo 100 > "$z1/brightness"
	echo "$rgbv" > "$z1/multi_intensity"
	# NO sleep here: the write above is still inside the 30ms debounce
	# window when the suspend starts - exactly the bug-4 scenario.
	rtcwake -m mem -s 20 >/dev/null 2>&1 || { fail "rtcwake failed"; break; }

	log "resumed; waiting for RGB resume repaint (1.5s + debounce)"
	sleep 4
	rb_mi=$(cat "$z1/multi_intensity")
	rb_ef=$(cat "$z1/effect")
	[ "$rb_mi" = "$rgbv" ] && pass "cycle $cycle: sysfs color retained ($label)" \
				|| fail "cycle $cycle: sysfs color '$rb_mi' != '$rgbv'"
	[ "$rb_ef" = "static" ] && pass "cycle $cycle: effect retained" \
				 || fail "cycle $cycle: effect '$rb_ef' != static"
	if kmsg_since_mark | grep -q "Failed to commit RGB state on suspend"; then
		warn "cycle $cycle: suspend commit reported failure (hid_dbg)"
	fi
	echo ">> VISUAL: $(basename "$z1") should be $label right now."
	cycle=$((cycle+1))
done

kmsg_check_fatal
kmsg_report_driver_errors
restore_zone_state "$z1" "$st"
echo
echo "NOTE: sysfs retention is necessary but not sufficient for bug 4 -"
echo "confirm visually that the LEDs show the last color set BEFORE each"
echo "suspend, not an older one. On pre-fix kernels the last write is"
echo "dropped and the previous color reappears after resume."
summary
