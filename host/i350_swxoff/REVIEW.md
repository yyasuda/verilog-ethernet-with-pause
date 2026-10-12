# Static and lifecycle review

## Build result

- Kernel headers: `6.8.0-138.138~22.04.1`
- Compiler: Ubuntu GCC `12.3.0-1ubuntu1~22.04.3` (same version as the kernel build)
- `make ... W=1 modules`: PASS, with no compiler or modpost warnings
- BTF: skipped because `vmlinux` was unavailable; this does not affect module loading
- Module name: `igb_swxoff`
- vermagic: `6.8.0-138-generic SMP preempt mod_unload modversions`
- `CONFIG_IGB=m`, `CONFIG_DEBUG_FS=y`
- Secure Boot: disabled, Platform Setup Mode

Artifacts:

```text
b215b2b6767e60082c3651dbda13277b14e5b7879a7fae12e8edc08e75c100ca  [historical verified module; binary not included]
b41cbf352f70a1b7a68d6a9277f877f3db6a065bd0bea34331dd085128b69a5d  igb_swxoff.patch
```

`checkpatch.pl --strict --no-tree --no-signoff`: 0 errors, 0 warnings, 0 checks. `patch --dry-run -p1` against the Canonical source tree passed.

## Lifecycle audit

### MMIO serialization

Only the delayed worker performs SWXOFF MMIO. The worker acquires RTNL before `swxoff_lock`. RTNL is the outer serialization for normal open/close, ethtool reconfiguration, MTU/ring changes, and reset work.

At the start of `igb_down()`, `__IGB_DOWN` is set and then `swxoff_lock` is acquired to make periodic/once state idle. If the worker already holds the lock, down proceeds after the SWXOFF write; if down runs first, the worker detects `__IGB_DOWN` and does not write.

PCI AER `igb_io_error_detected()` may call `igb_down()` without RTNL. This path also serializes down with the worker's MMIO interval using `swxoff_lock`; `netif_device_detach()` and the `__IGB_DOWN` guard apply as well.

### Cancel deadlock prevention

`igb_down()` calls only `cancel_delayed_work()`. There is no path where down holds RTNL, synchronously cancels a worker waiting for RTNL, and deadlocks.

debugfs `stop` excludes other commands with the command lock, makes the state idle under the state lock, releases all locks, and then calls `cancel_delayed_work_sync()`. The worker does not acquire the command lock.

remove sets removing/idle after debugfs removal and synchronously cancels without holding RTNL or the state lock. Only after completion does the existing igb remove path unmap BARs and free the adapter, so no worker remains after unmap/free. The implementation uses normal `debugfs_create_file()` and benefits from debugfs core file-removal protection.

### Command races and deadline

- `swxoff_command_lock`: serializes the complete write of `once`, `periodic`, and `stop`.
- `swxoff_lock`: protects mode, deadline, counters, remove state, and SWXOFF MMIO.
- New `once`/`periodic` commands while active return `-EBUSY`; start time and deadline are not overwritten.
- The 30-second deadline is set once when `periodic` is accepted.
- Each worker checks the absolute deadline both before transmission and before rescheduling.
- The final delay is `min(interval, deadline - jiffies)`, so no SWXOFF write occurs after the deadline.
- Link/down/reset failures stop periodic operation. Only `-EBUSY` from SWXOFF not self-clearing is retried within the deadline.

## Deliberately not verified yet

- Module unload/load and PCI rebind
- Runtime creation of the debugfs entry
- `TCTL.SWXOFF` write/self-clear
- XOFF frame wire transmission
- Increase of `tx_flow_control_xoff`
- KR260-side PAUSE reception and TX suppression
- Runtime behavior of natural timer expiry after stop and the 30-second automatic stop

These require NIC state changes and are deferred to a subsequent explicitly approved phase.
