# Intel I350 SWXOFF 実験用 driver 操作方法

`host/i350_swxoff/` は、Intel I350 の `TCTL.SWXOFF` を操作する一時的な実験用 `igb` driver です。汎用 driver や恒久インストーラではありません。

対象：

- PCI: `0000:43:00.1`
- Interface: `j10b`
- Device: Intel I350 `8086:1521`
- Kernel: `6.8.0-138-generic`
- 検証済み module SHA-256: `ae1d52b112fd250e2f1a06b887b8f9674be6cb50b1b9df5b872d2a7fdde587ab`

## ビルド準備

公開 tree には kernel source 本体は含まれていません。

対応する Ubuntu Canonical `linux-hwe-6.8` source package の `drivers/net/ethernet/intel/igb/` 一式を用意し、次の順番で patch を適用します。

```bash
cd /path/to/linux-source/drivers/net/ethernet/intel/igb

patch -p1 < /path/to/host/i350_swxoff/igb_swxoff.patch
patch -p1 < /path/to/host/i350_swxoff/debugfs_diagnostic.patch
```

外部 module 用 Makefile は、同じ Canonical source tree の object 構成を使用します。別 kernel release 用に推測して作り替えないでください。

ビルド対象 kernel は `6.8.0-138-generic`、headers は `6.8.0-138.138~22.04.1` です。

```bash
cd /path/to/standalone_pause_bridge/host/i350_swxoff
IGB_SOURCE_DIR=/path/to/patched/igb/source ./build.sh
```

生成物 `igb_swxoff.ko` の SHA-256、vermagic、対象 kernel が一致することを確認してから使用します。

## 事前条件

driver 交換中は、同じ `igb` に bind された NIC が一時的に停止します。独立した管理経路を使用し、`j10a` / `j10b` の binding と link 状態を保存してください。initramfs や autoload 設定は変更しません。

## driver の一時交換

```bash
sudo modprobe -r igb
sudo insmod /path/to/igb_swxoff.ko
lspci -nnk -s 43:00.1
ethtool j10b
```

`j10b` が対象 BDF に bind され、`1000Mb/s`、`Full`、`Link detected: yes` であることを確認してから操作します。

## debugfs

```bash
mount | grep debugfs
```

必要な場合：

```bash
sudo mount -t debugfs none /sys/kernel/debug
```

操作対象：

```bash
SWX=/sys/kernel/debug/igb_swxoff-0000:43:00.1
CTRL=$SWX/control
STATUS=$SWX/status
sudo cat "$STATUS"
```

## 単発 XOFF

```bash
echo once | sudo tee "$CTRL"
sudo cat "$STATUS"
```

`requests`、`register_triggers`、`tx_flow_control_xoff` の増加と `last_error=0` を確認します。

```bash
ethtool -S j10b | grep -E 'flow_control_xoff|flow_control_xon'
```

Software XON は実装していません。PAUSE timer の自然満了を待ちます。

## 周期 XOFF

単発試験が正常だった場合のみ使用します。

```bash
echo 'periodic 100' | sudo tee "$CTRL"
echo 'periodic 75' | sudo tee "$CTRL"
echo 'periodic 50' | sudo tee "$CTRL"
sudo cat "$STATUS"
```

停止：

```bash
echo stop | sudo tee "$CTRL"
sudo cat "$STATUS"
```

周期値は milliseconds です。worker には30秒の絶対 deadline があり、新しい周期コマンドで期限は延長されません。`FCTTV=0xffff`、1 Gb/s では1回の XOFF は約33.55 ms の PAUSE duration に相当します。

## 制限

- `FCTTV` と自動 flow-control 設定は変更しません。
- Software XON はありません。
- 対象 BDF 以外を SWXOFF 制御対象にしません。
- 操作には root 権限が必要です。

## 復元

```bash
echo stop | sudo tee "$CTRL"
sudo modprobe -r igb_swxoff
sudo modprobe igb
```

復元後に確認します。

```bash
lspci -nnk -s 43:00.0
lspci -nnk -s 43:00.1
ethtool j10a
ethtool j10b
test ! -e /sys/kernel/debug/igb_swxoff-0000:43:00.1/status
```

`j10a`/`j10b` の binding、link、PAUSE 設定、debugfs entry 消滅を確認して完了です。
