# Shared helpers for the Ally RGB test scripts. Source, don't execute.
# shellcheck shell=bash

LEDS_GLOB='/sys/class/leds/asus:rgb:key*'
RESULTS_DIR="${RESULTS_DIR:-/tmp/ally-rgb-results}"
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

c_red()   { printf '\033[31m%s\033[0m\n' "$*"; }
c_green() { printf '\033[32m%s\033[0m\n' "$*"; }
c_yell()  { printf '\033[33m%s\033[0m\n' "$*"; }

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
pass() { PASS_COUNT=$((PASS_COUNT+1)); c_green "PASS: $*"; }
fail() { FAIL_COUNT=$((FAIL_COUNT+1)); c_red   "FAIL: $*"; }
warn() { WARN_COUNT=$((WARN_COUNT+1)); c_yell  "WARN: $*"; }

require_root() {
	if [ "$(id -u)" -ne 0 ]; then
		c_red "This test must run as root (sysfs LED writes, unbind, suspend)."
		exit 1
	fi
	mkdir -p "$RESULTS_DIR"
}

# Zones present right now (may be empty mid-unbind).
find_zones() { ls -d $LEDS_GLOB 2>/dev/null; }

require_zones() {
	local zones
	zones=$(find_zones)
	if [ -z "$zones" ]; then
		fail "no asus:rgb:key* LED class devices found -" \
		     "is the PR branch kernel booted and hid-asus bound?"
		exit 1
	fi
	echo "$zones"
}

# hid-asus-bound Ally devices (vendor 0b05, PID 1abe Ally / 1b4c Ally X).
find_ally_hid_devs() {
	ls /sys/bus/hid/drivers/asus 2>/dev/null |
		grep -iE ':0B05:(1ABE|1B4C)\.' || true
}

# --- kernel log scanning -------------------------------------------------
# Baseline on the current kmsg sequence number so each test only scans
# messages it caused itself.
KMSG_BASELINE_FILE="$RESULTS_DIR/.kmsg_lines"

kmsg_mark() { dmesg | wc -l > "$KMSG_BASELINE_FILE"; }

kmsg_since_mark() {
	local n
	n=$(cat "$KMSG_BASELINE_FILE" 2>/dev/null || echo 0)
	dmesg | tail -n +"$((n+1))"
}

# Fatal patterns: any hit is an automatic test failure.
KMSG_FATAL_RE='BUG:|Oops|use-after-free|KASAN|general protection fault|list_del corruption|workqueue.*corrupt'
# Driver-level errors worth flagging (not necessarily fatal during stress).
KMSG_DRIVER_RE='Failed to set RGB effect|Failed to commit RGB state|asus.*[Ff]ail'

kmsg_check_fatal() {
	local hits
	hits=$(kmsg_since_mark | grep -E "$KMSG_FATAL_RE" || true)
	if [ -n "$hits" ]; then
		fail "kernel reported memory corruption / oops:"
		echo "$hits" | head -30
		return 1
	fi
	return 0
}

kmsg_report_driver_errors() {
	local hits
	hits=$(kmsg_since_mark | grep -E "$KMSG_DRIVER_RE" || true)
	[ -n "$hits" ] && { warn "driver errors in kernel log:"; echo "$hits" | head -20; }
	return 0
}

# --- zone state save/restore ---------------------------------------------
save_zone_state() { # $1 = zone dir, $2 = state file
	{
		cat "$1/multi_intensity"
		cat "$1/brightness"
		cat "$1/effect" 2>/dev/null || echo static
		cat "$1/speed" 2>/dev/null || echo 50
		cat "$1/enabled" 2>/dev/null || echo 1
	} > "$2"
}

restore_zone_state() { # $1 = zone dir, $2 = state file
	[ -r "$2" ] || return 0
	{
		read -r mi; read -r br; read -r ef; read -r sp; read -r en
		echo "$mi" > "$1/multi_intensity" 2>/dev/null
		echo "$br" > "$1/brightness"      2>/dev/null
		echo "$ef" > "$1/effect"          2>/dev/null
		echo "$sp" > "$1/speed"           2>/dev/null
		echo "$en" > "$1/enabled"         2>/dev/null
	} < "$2"
}

summary() {
	echo
	echo "==================== $(basename "$0") ===================="
	c_green "  passed: $PASS_COUNT"
	[ "$WARN_COUNT" -gt 0 ] && c_yell "  warnings: $WARN_COUNT"
	if [ "$FAIL_COUNT" -gt 0 ]; then
		c_red "  FAILED: $FAIL_COUNT"
		exit 1
	fi
	echo "  all good."
	exit 0
}
