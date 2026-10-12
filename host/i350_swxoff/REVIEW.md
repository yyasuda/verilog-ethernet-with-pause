# Static and lifecycle review

## Build result

- Kernel headers: `6.8.0-138.138~22.04.1`
- Compiler: Ubuntu GCC `12.3.0-1ubuntu1~22.04.3`（kernel buildと同一version）
- `make ... W=1 modules`: PASS、compiler/modpost warningなし
- BTF: `vmlinux`不在のためskip。module load可否には影響しない。
- module name: `igb_swxoff`
- vermagic: `6.8.0-138-generic SMP preempt mod_unload modversions`
- `CONFIG_IGB=m`、`CONFIG_DEBUG_FS=y`
- Secure Boot: disabled、Platform Setup Mode

成果物：

```text
b215b2b6767e60082c3651dbda13277b14e5b7879a7fae12e8edc08e75c100ca  [historical verified module; binary not included]
b41cbf352f70a1b7a68d6a9277f877f3db6a065bd0bea34331dd085128b69a5d  igb_swxoff.patch
```

`checkpatch.pl --strict --no-tree --no-signoff`: 0 errors、0 warnings、0 checks。
patchはCanonical source treeに対する`patch --dry-run -p1`がPASSした。

## Lifecycle audit

### MMIO serialization

SWXOFF MMIOはdelayed workerだけが行う。workerはRTNLを取得してから
`swxoff_lock`を取得する。通常のopen/close、ethtool reconfiguration、MTU/ring変更、
reset workとの関係ではRTNLが最外周のserializationとなる。

`igb_down()`冒頭では`__IGB_DOWN`設定後に`swxoff_lock`を取得してperiodic/once状態を
idle化する。そのため、workerが既にlock内ならSWXOFF write完了後にdownが進み、downが
先ならworkerは`__IGB_DOWN`を検出して書かない。

PCI AER `igb_io_error_detected()`はRTNLなしで`igb_down()`を呼び得る。この経路でも
`swxoff_lock`がworkerのMMIO区間とdownを直列化し、`netif_device_detach()`と
`__IGB_DOWN` guardも作用する。

### Cancel deadlock prevention

`igb_down()`は`cancel_delayed_work()`のみを呼ぶ。workerがRTNL待ちの状態で、RTNLを
保持したdown側が同期cancelして相互待ちになる経路はない。

debugfs `stop`はcommand lockで他commandを排除し、state lock内でidle化してからlockを
すべて解放し、その後`cancel_delayed_work_sync()`する。workerはcommand lockを取得しない。

removeはdebugfs removal後にremoving/idleを設定し、RTNLもstate lockも保持しない状態で
同期cancelする。その完了後に既存igb remove処理がBAR unmapとadapter freeへ進むため、
unmap/free後にworkerは残らない。通常の`debugfs_create_file()`を使用しており、debugfs coreの
file-removal protectionも有効である。

### Command races and deadline

- `swxoff_command_lock`: `once`、`periodic`、`stop`のwrite全体を直列化する。
- `swxoff_lock`: mode、deadline、counter、remove stateとSWXOFF MMIOを保護する。
- active中の新しい`once`/`periodic`は`-EBUSY`。開始時刻/deadlineを上書きしない。
- 30秒deadlineは`periodic`受理時に一度だけ設定する。
- 各workerは送信前と再schedule前の両方で絶対deadlineを確認する。
- 最後のdelayは`min(interval, deadline - jiffies)`なので、deadlineに状態を停止へ遷移する
  workerは動くが、deadline以後のSWXOFF writeは行わない。
- link/down/reset等の失敗は周期動作を停止する。`SWXOFF`未self-clearの`-EBUSY`だけは
  deadline内で再試行する。

## Deliberately not verified yet

- module unload/loadとPCI rebind
- debugfs entryの実機生成
- `TCTL.SWXOFF` write/self-clear
- XOFF frame wire transmission
- `tx_flow_control_xoff`増加
- KR260側PAUSE受信・送信抑制
- stop後の自然満了と30秒自動停止のruntime挙動

これらはNIC状態変更を伴う次工程として、明示承認後に実施する。
