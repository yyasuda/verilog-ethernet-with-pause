# Intel I350 SWXOFF 参照 driver

[English version](README.md)

このディレクトリには、KR260 PAUSE bridge で使用した一時的な `igb` 実験用の参照資料を収録しています。汎用 driver、installer、またはサポート対象の kernel module ではありません。

## 目的

この patch は、Intel I350 の `TCTL.SWXOFF` bit を書き込んで IEEE 802.3x PAUSE XOFF を要求する、対象限定の debugfs control を追加します。`FCTTV` と自動 flow-control 設定は変更しません。Software XON は実装していません。

## 対象と source

- Intel I350 `8086:1521`、対象 BDF `0000:43:00.1`（`j10b`）
- Ubuntu `6.8.0-138-generic`
- Canonical `linux-hwe-6.8` source package `6.8.0-138.138~22.04.1`
- 対応する `/lib/modules/6.8.0-138-generic/build` に対して build
- 検証済み module SHA-256: `ae1d52b112fd250e2f1a06b887b8f9674be6cb50b1b9df5b872d2a7fdde587ab`

patch の適用順序：

1. Canonical の `drivers/net/ethernet/intel/igb` source tree に `igb_swxoff.patch` を適用する。
2. 診断用 probe/error logging が必要な場合は `debugfs_diagnostic.patch` も適用する。
3. patched `igb` directory を `IGB_SOURCE_DIR` に指定（またはこの directory に `source/` として配置）し、対応 kernel headers とともに `./build.sh` を実行する。公開 tree に `source/` は意図的に含めていない。

検証済み external-module Makefile は、対応する Canonical `drivers/net/ethernet/intel/igb` tree のものです。

```make
# SPDX-License-Identifier: GPL-2.0
obj-m += igb_swxoff.o
igb_swxoff-objs := igb_main.o igb_ethtool.o e1000_82575.o \\
    e1000_mac.o e1000_nvm.o e1000_phy.o e1000_mbx.o \\
    e1000_i210.o igb_ptp.o igb_hwmon.o
```

対応する Ubuntu kernel source package から完全な `igb` directory をコピーし、上記順序で2つの patch を適用してください。元の Makefile と、この external-module object list を保持します。別の kernel release 用の Makefile を推測して作成しないでください。

binary `.ko`、kernel source tree、build intermediate は意図的に含めていません。

コピーした wrapper にある `P4FAB_J10B_DISABLE_PAUSE` は、過去の診断用 macro に過ぎません。通常 build では未定義のため PAUSE は有効なままです。この参照 driver は FPGA 側の PAUSE enable を制御しません。

## debugfs ABI

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

周期 worker には30秒の絶対 deadline があります。`FCTTV=0xffff`、1 Gb/s では、1回の XOFF は約33.55 ms の PAUSE time に相当します。100/75/50 ms は実験上の停止・再開条件であり、hardware configuration value ではありません。

## 安全性と復元

root 権限と一時的な stock driver 交換が必要です。実験 module の unload/reload 中は、その module に bind された全 function が影響を受けます。独立した管理経路を使用し、traffic 送信前に link と binding を確認してください。SWXOFF control の対象は対象 BDF に限定されています。

```bash
sudo modprobe -r igb_swxoff   # external module が install されていない場合は rmmod を使用
sudo modprobe igb
```

両 PCI function の binding、link state、PAUSE 設定、復元後の debugfs directory 消滅を確認してください。この資料は initramfs や autoload configuration へ install しません。

## Evidence

`evidence/` directory には、単発 XOFF と periodic propagation の匿名化済み記録があります。検証済み単発試験では `tx_flow_control_xoff` delta `+1` を記録しました。propagation record と bridge benchmark record には観測 counter と復元結果を記載していますが、完全 lossless を保証する主張ではありません。

## License

この patch は Canonical Linux `igb` driver の derivative work です。元の SPDX/copyright notice を保持し、適用される Linux kernel license 条件に従ってのみ配布してください。`SOURCE.md` に Canonical package と source hash、`REVIEW.md` に元の static review を記載しています。この patch は独立 driver として再ライセンスしていません。
