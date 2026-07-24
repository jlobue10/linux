#!/bin/bash
# run-all: run the non-disruptive tests in order, then optionally the
# suspend test. Writes a combined log under /tmp/ally-rgb-results.
#
#   ./run-all.sh                 # 00, 01 (non-interactive), 02, 04, 05
#   ./run-all.sh --with-suspend  # also 03 (device WILL suspend, 3 cycles)
#   ./run-all.sh --interactive   # 01 pauses for visual confirmation
set -u
cd "$(dirname "$0")"
RESULTS_DIR="${RESULTS_DIR:-/tmp/ally-rgb-results}"
export RESULTS_DIR
mkdir -p "$RESULTS_DIR"
MAIN_LOG="$RESULTS_DIR/run-all.$(date +%Y%m%d-%H%M%S).log"

WITH_SUSPEND=0; INTERACTIVE_FLAG=""
for a in "$@"; do
	case "$a" in
		--with-suspend) WITH_SUSPEND=1 ;;
		--interactive)  INTERACTIVE_FLAG="--interactive" ;;
		*) echo "unknown flag: $a"; exit 2 ;;
	esac
done

declare -A RESULT
run() {
	local name=$1; shift
	echo | tee -a "$MAIN_LOG"
	echo "########## $name $* ##########" | tee -a "$MAIN_LOG"
	if "./$name" "$@" 2>&1 | tee -a "$MAIN_LOG"; then
		RESULT[$name]=PASS
	else
		RESULT[$name]=FAIL
	fi
}

run 00-env-check.sh
run 01-basic-function.sh $INTERACTIVE_FLAG
run 02-debounce-stress.sh
run 04-unbind-stress.sh
[ "$WITH_SUSPEND" = 1 ] && run 03-suspend-resume.sh
run 05-collect-logs.sh

echo
echo "==================== OVERALL ===================="
rc=0
for t in 00-env-check.sh 01-basic-function.sh 02-debounce-stress.sh \
	 04-unbind-stress.sh 03-suspend-resume.sh 05-collect-logs.sh; do
	[ -n "${RESULT[$t]:-}" ] || continue
	printf '  %-24s %s\n' "$t" "${RESULT[$t]}"
	[ "${RESULT[$t]}" = FAIL ] && rc=1
done
echo "full log: $MAIN_LOG"
exit $rc
