# Static and lifecycle review

## Build result

- Kernel headers: `6.8.0-138.138~22.04.1`
- Compiler: Ubuntu GCC `12.3.0-1ubuntu1~22.04.3`（kernel build と同じ version）
- `make ... W=1 modules`: PASS、compiler/modpost warning なし
- BTF: `vmlinux` 不在のため skip。module load 可否には影響しない
- module name: `igb_swxoff`
- vermagic: `6.8.0-138-generic SMP preempt mod_unload modversions`
- `CONFIG_IGB=m`、`CONFIG_DEBUG_FS=y`
- Secure Boot: disabled、Platform Setup Mode

成果物：

```text
b215b2b6767e60082c3651dbda13277b14e5b7879a7fae12e8edc08e75c100ca  [historical verified module; binary not included]
b41cbf352f70a1b7a68d6a9277f877f3db6a065bd0bea34331dd085128b69a5d  igb_swxoff.patch
```

`checkpatch.pl --strict --no-tree --no-signoff`: 0 errors、0 warnings、0 checks。patch は Canonical source tree に対する `patch --dry-run -p1` が PASS しました。

## Lifecycle audit

### MMIO serialization

SWXOFF MMIO は delayed worker だけが行います。worker は RTNL を取得してから `swxoff_lock` を取得します。通常の open/close、ethtool reconfiguration、MTU/ring 変更、reset work との関係では RTNL が最外周の serialization です。

`igb_down()` 冒頭では `__IGB_DOWN` 設定後に `swxoff_lock` を取得して periodic/once 状態を idle 化します。そのため、worker が既に lock 内なら SWXOFF write 完了後に down が進み、down が先なら worker は `__IGB_DOWN` を検出して書きません。

PCI AER `igb_io_error_detected()` は RTNL なしで `igb_down()` を呼び得ます。この経路でも `swxoff_lock` が worker の MMIO 区間と down を直列化し、`netif_device_detach()` と `__IGB_DOWN` guard も作用します。

### Cancel deadlock prevention

`igb_down()` は `cancel_delayed_work()` のみを呼びます。worker が RTNL 待ちの状態で、RTNL を保持した down 側が同期 cancel して相互待ちになる経路はありません。

debugfs `stop` は command lock で他 command を排除し、state lock 内で idle 化してからすべての lock を解放し、その後 `cancel_delayed_work_sync()` します。worker は command lock を取得しません。

remove は debugfs removal 後に removing/idle を設定し、RTNL も state lock も保持しない状態で同期 cancel します。その完了後に既存 igb remove 処理が BAR unmap と adapter free へ進むため、unmap/free 後に worker は残りません。通常の `debugfs_create_file()` を使用しており、debugfs core の file-removal protection も有効です。

### Command races and deadline

- `swxoff_command_lock`: `once`、`periodic`、`stop` の write 全体を直列化
- `swxoff_lock`: mode、deadline、counter、remove state、SWXOFF MMIO を保護
- active 中の新しい `once`/`periodic` は `-EBUSY`。開始時刻/deadline は上書きしない
- 30 秒 deadline は `periodic` 受理時に一度だけ設定
- 各 worker は送信前と再 schedule 前の両方で絶対 deadline を確認
- 最後の delay は `min(interval, deadline - jiffies)`。deadline 以後の SWXOFF write は行わない
- link/down/reset 等の失敗は周期動作を停止。`SWXOFF` 未 self-clear の `-EBUSY` だけは deadline 内で再試行

## Deliberately not verified yet

- module unload/load と PCI rebind
- debugfs entry の実機生成
- `TCTL.SWXOFF` write/self-clear
- XOFF frame wire transmission
- `tx_flow_control_xoff` 増加
- KR260 側 PAUSE 受信・送信抑制
- stop 後の自然満了と30秒自動停止の runtime 挙動

これらは NIC 状態変更を伴う次工程として、明示承認後に実施します。
