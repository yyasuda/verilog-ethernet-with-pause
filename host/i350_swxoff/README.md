# Intel I350 SWXOFF reference driver

[日本語版](README.ja.md)

This directory contains reference material for the temporary `igb` experiment used with the KR260 PAUSE bridge. It is not a general-purpose driver, installer, or supported kernel module.

## Purpose

The patch adds a target-limited debugfs control that writes the Intel I350 `TCTL.SWXOFF` bit to request an IEEE 802.3x PAUSE XOFF. `FCTTV` and automatic flow-control configuration are unchanged; software XON is not implemented.

## Target and source

- Intel I350 `8086:1521`, target BDF `0000:43:00.1` (`j10b`). Here, `j10a`/`j10b` mean the host Ethernet interfaces directly connected to KR260 J10A/J10B.
- Ubuntu `6.8.0-138-generic`
- Canonical `linux-hwe-6.8` source package `6.8.0-138.138~22.04.1`
- Build against the matching `/lib/modules/6.8.0-138-generic/build`
- Verified module SHA-256: `ae1d52b112fd250e2f1a06b887b8f9674be6cb50b1b9df5b872d2a7fdde587ab`

Use a built `igb_swxoff.ko` only after verifying its SHA-256, vermagic, and target kernel version.

The patch order is:

1. Apply `igb_swxoff.patch` to the Canonical `drivers/net/ethernet/intel/igb` source tree.
2. Optionally apply `debugfs_diagnostic.patch` for diagnostic probe/error logging.
3. Set `IGB_SOURCE_DIR` to that patched `igb` directory (or place it in this directory as `source/`) and run `./build.sh` with the matching kernel headers. The public tree intentionally does not contain `source/`.

The validated external-module Makefile is the one from the matching Canonical `drivers/net/ethernet/intel/igb` tree:

```make
# SPDX-License-Identifier: GPL-2.0
obj-m += igb_swxoff.o
igb_swxoff-objs := igb_main.o igb_ethtool.o e1000_82575.o \\
    e1000_mac.o e1000_nvm.o e1000_phy.o e1000_mbx.o \\
    e1000_i210.o igb_ptp.o igb_hwmon.o
```

Prepare the source directory by copying the complete `igb` directory from the matching Ubuntu kernel source package, applying the two patches in the order above, and retaining its original Makefile plus this external-module object list. Do not invent a Makefile from a different kernel release.

The binary `.ko`, kernel source tree, and build intermediates are intentionally not included.

## Debugfs ABI

```bash
SWX=/sys/kernel/debug/igb_swxoff-0000:43:00.1
CTRL=$SWX/control
STATUS=$SWX/status

echo once | sudo tee "$CTRL"
echo 'periodic 100' | sudo tee "$CTRL"
echo 'periodic 75'  | sudo tee "$CTRL"
echo 'periodic 50'  | sudo tee "$CTRL"
echo stop | sudo tee "$CTRL"
sudo cat "$STATUS"
```

The periodic worker has a 30-second absolute deadline. At `FCTTV=0xffff` and 1 Gb/s, one XOFF represents approximately 33.55 ms of PAUSE time. The 100/75/50 ms values are experimental stop/resume conditions, not hardware configuration values.

## Temporary driver replacement

```bash
sudo modprobe -r igb
sudo insmod /path/to/igb_swxoff.ko
lspci -nnk -s 43:00.1
ethtool j10b
```

Confirm that `j10b` is bound to the target BDF and reports `1000Mb/s`, `Full`, and `Link detected: yes` before using debugfs. After a single XOFF, check that `requests`, `register_triggers`, and `tx_flow_control_xoff` increased and that `last_error=0`.

```bash
ethtool -S j10b | grep -E 'flow_control_xoff|flow_control_xon'
```

## Safety and recovery

Root permission and temporary stock-driver replacement are required. All functions bound to the experimental module are affected during unload/reload; use an independent management path and verify link/binding before sending traffic. The module is restricted to the target BDF for SWXOFF control.

```bash
sudo modprobe -r igb_swxoff   # use rmmod if the external module is not installed
sudo modprobe igb
```

Verify both PCI bindings, link state, PAUSE settings, and removal of the debugfs directory after recovery. This material does not install into initramfs or autoload configuration.

Example recovery checks:

```bash
lspci -nnk -s 43:00.0
lspci -nnk -s 43:00.1
ethtool j10a
ethtool j10b
test ! -e /sys/kernel/debug/igb_swxoff-0000:43:00.1/status
```

## Evidence

The `evidence/` directory contains sanitized records for single XOFF and periodic propagation. The validated single test recorded `tx_flow_control_xoff` delta `+1`. The propagation record and the bridge benchmark record document observed counters and recovery; observations are not claims of guaranteed losslessness.

## License

The patch is a derivative of the Canonical Linux `igb` driver. Preserve the original SPDX/copyright notices and distribute it only under the applicable Linux kernel license terms. `SOURCE.md` identifies the Canonical package and source hashes; `REVIEW.md` records the original static review. The patch is not a relicensed standalone driver.
