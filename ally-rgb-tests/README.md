# ROG (Xbox) Ally X — RGB work-queue test suite

On-device tests for the RGB zone LED support ("HID: asus: tmp leds") and
the work-queue lifecycle fixes on this branch
(`claude/rgb-work-queue-debug-7pxw0g`, PR #2). **Not for upstream** — drop
this directory's commit before submitting the series anywhere.

## Prerequisites

- The **PR branch kernel booted** on the device, built with
  `CONFIG_HID_ASUS=y` (or `=m`, loaded) and `CONFIG_LEDS_CLASS_MULTICOLOR=y`.
  For test 04, one run on a `CONFIG_KASAN=y` build is strongly recommended.
- Root. Run from a **local console** for test 03 (the device suspends).
- `rtcwake` (util-linux) for test 03.

## Quick start

```sh
cd ally-rgb-tests
sudo ./run-all.sh                # everything except suspend
sudo ./run-all.sh --with-suspend # includes 3 real suspend cycles
sudo ./run-all.sh --interactive  # 01 asks you to confirm colors visually
```

Each script also runs standalone. Results and a shareable log tarball land
in `/tmp/ally-rgb-results/` (override with `RESULTS_DIR=...`).

## What each test covers

| Script | What it does | Maps to |
|---|---|---|
| `00-env-check.sh` | device/kernel/driver/zone sanity, read-only | preflight |
| `01-basic-function.sh` | every attr of every zone: colors, brightness, all effects + aliases, speed tiers, enabled gate, invalid-input rejection | basic RGB function |
| `02-debounce-stress.sh` | 300 rapid writes/zone sequential + all zones concurrently; must coalesce via the 30 ms delayed work, settle on final value, no dmesg errors | debounce/work-queue behavior |
| `03-suspend-resume.sh` | writes a distinct color and suspends **inside the debounce window**, 3 cycles; color must survive resume. `MCU_POWERSAVE=1` env forces the USB re-enumeration (reset_resume) path | **bug 4** (suspend dropped last write), resume repaint |
| `04-unbind-stress.sh` | 50× driver unbind/rebind with a concurrent sysfs writer; scans kmsg for BUG/KASAN/UAF/oops each iteration; verifies zones re-register | **bugs 1–3** (queue-after-cancel UAF, resume TOCTOU, probe error path) |
| `05-collect-logs.sh` | bundles dmesg/journal/DMI/zone state into a tarball | reporting |

Expected on a **pre-fix** kernel: 03 shows the previous color after resume
(sysfs may still read the new one — trust the LEDs); 04 can oops or splat
under KASAN. On the **fixed** kernel everything passes; transient
`-ENODEV` writes during 04's unbind windows are expected and ignored.

## Reporting back

Attach `/tmp/ally-rgb-results/ally-rgb-logs-*.tar.gz` (from
`05-collect-logs.sh`) plus a note of visual results for 03 to PR #2:
https://github.com/jlobue10/linux/pull/2
