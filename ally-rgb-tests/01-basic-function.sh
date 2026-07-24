#!/bin/bash
# 01-basic-function: exercise every attribute of every zone once.
# With --interactive, pauses for visual confirmation at each step.
set -u
cd "$(dirname "$0")" && . ./lib.sh
require_root
INTERACTIVE=0
[ "${1:-}" = "--interactive" ] && INTERACTIVE=1

confirm() { # $1 = what the tester should see
	if [ "$INTERACTIVE" = 1 ]; then
		read -r -p "  >> Do you see: $1 ? [Y/n] " a
		case "$a" in n*|N*) fail "visual check: $1" ;; *) pass "visual check: $1" ;; esac
	else
		log "  (visual: expect $1)"
		sleep 1
	fi
}

try_write() { # $1 = value, $2 = file, $3 = description
	if echo "$1" > "$2" 2>/dev/null; then
		pass "$3"
	else
		fail "$3 (write '$1' to $2 rejected)"
	fi
}

expect_reject() { # $1 = value, $2 = file, $3 = description
	if echo "$1" > "$2" 2>/dev/null; then
		fail "$3: invalid value '$1' was accepted"
	else
		pass "$3"
	fi
}

zones=$(require_zones)
kmsg_mark

for z in $zones; do
	name=$(basename "$z")
	log "=== $name (zone: $(cat "$z/zone" 2>/dev/null || echo ?)) ==="
	st="$RESULTS_DIR/$name.state"
	save_zone_state "$z" "$st"

	# solid colors through the multicolor API
	try_write "static" "$z/effect" "$name: effect=static"
	try_write 100 "$z/brightness" "$name: brightness=100"
	for color in "255 0 0:red" "0 255 0:green" "0 0 255:blue" "255 255 255:white"; do
		rgbv=${color%%:*}; label=${color##*:}
		try_write "$rgbv" "$z/multi_intensity" "$name: color $label"
		confirm "$name solid $label"
	done

	# brightness scaling (bounded 0..100 per cdev->max_brightness)
	try_write 50 "$z/brightness" "$name: brightness=50"
	confirm "$name dimmed to half"
	try_write 0 "$z/brightness" "$name: brightness=0"
	confirm "$name off"
	try_write 100 "$z/brightness" "$name: brightness=100"

	# effects, incl. the aliases the store accepts
	for e in $(cat "$z/effect_index"); do
		try_write "$e" "$z/effect" "$name: effect=$e"
		[ "$(cat "$z/effect")" = "$e" ] || fail "$name: effect readback != $e"
		confirm "$name running '$e'"
	done
	expect_reject "disco" "$z/effect" "$name: bogus effect rejected"

	# speed maps to 3 hw tiers: <=33 slow, <=66 medium, >66 fast
	try_write "breathing" "$z/effect" "$name: effect=breathing (for speed test)"
	for s in 10 50 90; do
		try_write "$s" "$z/speed" "$name: speed=$s"
		confirm "$name breathing speed step ($s/100)"
	done
	expect_reject 101 "$z/speed" "$name: speed>100 rejected"

	# enabled gate (sends zeroed colors while off, state preserved)
	try_write 0 "$z/enabled" "$name: enabled=0"
	confirm "$name dark while enabled=0"
	try_write 1 "$z/enabled" "$name: enabled=1"
	confirm "$name lit again"

	restore_zone_state "$z" "$st"
done

# give the 30ms debounced work time to drain, then check the kernel log
sleep 1
kmsg_check_fatal
kmsg_report_driver_errors
summary
