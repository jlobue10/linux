#!/bin/bash
# 02-debounce-stress: hammer the debounced work queue. Rapid writes must
# coalesce (30ms delayed work), settle on the final value, and log no
# errors. Also drives all four zones concurrently.
set -u
cd "$(dirname "$0")" && . ./lib.sh
require_root
WRITES=${WRITES:-300}

zones=$(require_zones)
kmsg_mark

for z in $zones; do
	st="$RESULTS_DIR/$(basename "$z").state"
	save_zone_state "$z" "$st"
done

log "phase 1: $WRITES sequential brightness writes per zone"
for z in $zones; do
	name=$(basename "$z")
	i=0; errs=0
	while [ $i -lt "$WRITES" ]; do
		echo $((i % 101)) > "$z/brightness" 2>/dev/null || errs=$((errs+1))
		i=$((i+1))
	done
	echo 77 > "$z/brightness"
	sleep 0.2   # let the trailing debounced work run
	rb=$(cat "$z/brightness")
	[ "$errs" -eq 0 ] && pass "$name: $WRITES writes, no errors" \
			  || fail "$name: $errs of $WRITES writes failed"
	[ "$rb" = 77 ] && pass "$name: settled on final value (77)" \
			|| fail "$name: readback $rb != 77"
done

log "phase 2: all zones hammered concurrently (colors + effects)"
pids=""
for z in $zones; do
	(
		i=0
		while [ $i -lt "$WRITES" ]; do
			echo "$((i%256)) $(( (i*7)%256 )) $(( (i*13)%256 ))" > "$z/multi_intensity" 2>/dev/null
			[ $((i % 50)) -eq 0 ] && echo breathing > "$z/effect" 2>/dev/null
			[ $((i % 50)) -eq 25 ] && echo static > "$z/effect" 2>/dev/null
			i=$((i+1))
		done
	) & pids="$pids $!"
done
rc=0
for p in $pids; do wait "$p" || rc=1; done
[ $rc -eq 0 ] && pass "concurrent hammer completed" || fail "a hammer subshell died"

sleep 1
kmsg_check_fatal
kmsg_report_driver_errors

for z in $zones; do
	restore_zone_state "$z" "$RESULTS_DIR/$(basename "$z").state"
done
summary
