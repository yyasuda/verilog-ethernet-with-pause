# PAUSE completion-time benchmark (2026-10-12)

Runtime image was unchanged (`c6e7382d59820537f94b61c6291fd2fec149226eb26022ffa5242e59ba724164`).
The experimental module hash was `ae1d52b112fd250e2f1a06b887b8f9674be6cb50b1b9df5b872d2a7fdde587ab`.
All runs used 1500-byte frames, the corrected concurrent `runtime_forward.py`, requested `SO_RCVBUF=16 MiB`, and no pacing.

## Baseline scaling (stock igb, no forced XOFF)

| frames | received | missing | mismatch | elapsed (s) |
|---:|---:|---:|---|---:|
| 5,000 | 5,000 | 0 | no | 0.07597 |
| 10,000 | 10,000 | 0 | no | 0.14098 |
| 20,000 | 20,000 | 0 | no | 0.26798 |
| 40,000 | 40,000 | 0 | no | 0.51398 |

The 40,000-frame condition was selected. NIC TX/RX deltas matched the frame count and CRC/frame/missed/error counters stayed zero.

## Periodic XOFF (40,000 × 1500 bytes)

| condition | elapsed (s) | received | missing | mismatch | j10b TX XOFF | j10a RX XOFF | j10a RX XON |
|---|---:|---:|---:|---:|---:|---:|---:|
| none | 0.51398 | 40,000 | 0 | no | 0 | 0 | 0 |
| 100 ms | 0.85802 | 40,000 | 0 | no | 45 | 16,349 | 8 |
| 50 ms | 1.99899 | 40,000 | 0 | no | 115 | 79,213 | 39 |
| 16 ms | 6.11599 | 0 | 40,000 | yes | 484 | 361,732 | 0 |
| 25 ms attempt | 0.51098 | 40,000 | 0 | no | 0 | 0 | 0 |

All successful runs had zero NIC CRC/frame/missed/error deltas. The 16 ms condition is a failure, not a lossless result: it approached continuous PAUSE, produced no received frames, and debugfs reported `last_error=-5` after stop. It is excluded from the usable comparison.

The 100 ms and 50 ms results demonstrate a monotonic completion-time increase while retaining exact content and full count. The counter values are hardware counters; application receive counts are reported separately.

The 25 ms attempt is **not a valid periodic-XOFF result**.  The debugfs status showed `requests=1`, `register_triggers=0`, and `last_error=-67`; j10b `tx_flow_control_xoff` and j10a `rx_flow_control_xoff` both remained zero.  Its 0.51098 s completion therefore represents an ordinary no-XOFF transfer, not a 25 ms PAUSE comparison.

## 25 ms retry after link recovery

Source inspection shows `igb_swxoff_trigger_locked()` returns `-ENOLINK` when `!netif_carrier_ok(netdev)`, before checking duplex, TCTL.EN, or SWXOFF.  After a later module replacement, the test waited until ethtool reported 1000 Mb/s/full/link=yes.  A single `once` then passed (`requests=1`, `register_triggers=1`, `last_error=0`, `tx_flow_control_xoff` delta +1).

With that verified link, `periodic 25` initially started correctly (`requests=10`, `register_triggers=10`, `last_error=0`).  The 40,000-frame run nevertheless ended with zero received frames; after stop the status was `requests=348`, `register_triggers=347`, `last_error=-5`, and j10b TX XOFF delta 343.  j10a RX XOFF delta was 308,077; NIC CRC/frame/missed/error deltas were zero.  The driver therefore did issue many XOFF frames, but the 25 ms condition drove the target into a sustained-stop/failure state.  It is not a valid lossless completion-time point.  The exact `-EIO` trigger is the source path's `TCTL.EN` check; no source change was made.

## 75 ms periodic-XOFF

After module load, link recovery was explicitly verified (`1000Mb/s`, `link=yes`) before starting periodic mode. For 40,000 frames × 1500 bytes:

| elapsed (s) | received | missing | mismatch | j10b TX XOFF | j10a RX XOFF | j10a RX XON |
|---:|---:|---:|---|---:|---:|---:|
| 1.183999 | 40,000 | 0 | no | 65 | 30,591 | 15 |

Debugfs ended with `requests=65`, `register_triggers=65`, `last_error=0`. j10a TX and j10b RX deltas were 40,009 and 40,004 respectively; CRC/frame/missed/error deltas were zero. This is a valid PAUSE completion-time point between the 100 ms and 50 ms results.

## Restore

Periodic transmission was stopped. The experimental module was explicitly removed with `rmmod igb_swxoff` and stock `igb` was loaded. Both 43:00.0 and 43:00.1 are bound to stock `igb`, both links are 1000 Mb/s/full/up, and the experimental debugfs directory is absent.
