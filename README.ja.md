# KR260 verilog-ethernet + PAUSE 2ポート・ブリッジ例

[English version](README.md)

公開予定 repository: `verilog-ethernet-with-pause`  
GitHub description: `IEEE 802.3x PAUSE flow-control example using verilog-ethernet on AMD Kria KR260.`

このディレクトリは、05e-4a minimal cross-connect の検証結果から抽出した独立した実験用 source example です。RC2 repository、製品、または KR260 用 turnkey 配布物ではありません。

## アーキテクチャ

```text
J10A DP83867/RGMII
  -> verilog-ethernet MAC + PAUSE RX/TX + RX frame store
  -> static_dual_crossconnect
  -> TX frame store + verilog-ethernet MAC + PAUSE RX/TX
  -> J10B DP83867/RGMII
```

逆方向も対称です。両ポートの PAUSE RX/TX は compile-time で常時有効で、検証済みの watermark、quanta、refresh 設定を維持します。PAUSE frame は MAC の control path で消費され、通常データとして転送されません。

## 内容

- `rtl/`: verilog-ethernet MAC/RGMII、RX/TX store、watermark controller、PHY helper、`static_dual_crossconnect.sv`。
- `rtl/standalone_pause_bridge_pl.sv`: PL の port/interface contract。固定 cross-connect を持ち、検証済み MAC/store/CDC 接続は platform prerequisite module `kr260_pause_bridge_platform` と `kr260_pause_bridge_endpoints` に委ねます。
- `constraints/`: 検証済み variant で使用した KR260 dual-RGMII constraints。
- `sim/`: static cross-connect と datapath の testbench source。
- `host/`: concurrent AF_PACKET forwarding test と測定記録。
- `host/i350_swxoff/`: 一時的な I350 XOFF driver の参照用 patch、build notes、provenance、review、匿名化した hardware evidence。kernel module binary は含みません。
- `tcl/`: 既存の implementation constraint hook。VNP4/PS/generated-IP infrastructure を生成する production Tcl は意図的に含めていません。

## ビルド境界

これは source-only example です。完全な Vivado top には、board 固有の PS/clock/MDIO wrapper と generated platform IP が必要です。05e production top は VNP4 と RC2 固有 interface を含むため、それらの platform file は含めていません。VNP4、P4、GEM2 packet datapath、generated IP、bitstream、XSA、BootFW、FIT、DTB は含みません。

追加した PL file 自体は source-only であり、単独で hardware-qualified ではありません。static elaboration には、記載した2つの platform module、`axis_clock_converter`、AMD RGMII primitive、XPM CDC definition が必要です。platform endpoint module は検証済み05e endpoint接続を再現する必要があり、新しい datapath や PAUSE logic は定義していません。

PL top の `j10a_phy_mdio` と `j10b_phy_mdio` は integration boundary に過ぎません。示されている assign は完成した双方向 MDIO 実装ではなく、実際の I/O buffer、tri-state direction、Clause-22 MDIO master は platform wrapper 側で提供する必要があります。

Vivado 2026.1、KR260 carrier 2.0 pinout、`DEPENDENCIES.md` に記載した verilog-ethernet revision を使用してください。このディレクトリだけで任意の KR260 環境に再現可能とは考えないでください。

## Hardware 前提

- KR260 carrier 2.0、J10A/J10B DP83867 PHY、1GbE RGMII。
- 既存の PS clock/reset と MDIO 初期化環境。
- J10B RX IDELAY 1000 ps の timing-clean 検証済み implementation。その他の PHY delay と clock-root 値は platform 固有です。
- FPGA Manager runtime load は既存 platform が担当し、この example は install automation を提供しません。

## Forwarding test

```text
sudo python3 host/runtime_forward.py j10a j10b --count 40000 --length 1500 --rcvbuf 16777216
```

receiver は sender と並行実行され、frame count、到着順、payload を検証します。現在の軽量 script は duplicate sequence number を独立検出しません。`duplicate` field が zero でも、独立した duplicate audit の結果とは解釈しないでください。要求した receive buffer は host の `net.core.rmem_max` により制限される場合があります。

## PAUSE 測定例

検証済み runtime image 上で、J10A から J10B へ 1500-byte frame を40,000個送り、I350 j10b の software XOFF を使用して取得した測定値です。

| XOFF interval | Completion time | Received | Missing | Payload mismatch |
|---|---:|---:|---:|---:|
| None | 0.51398 s | 40,000 | 0 | 0 |
| 100 ms | 0.85802 s | 40,000 | 0 | 0 |
| 75 ms | 1.183999 s | 40,000 | 0 | 0 |
| 50 ms | 1.99899 s | 40,000 | 0 | 0 |

これは1つの検証済み hardware image における測定であり、一般的な性能保証ではありません。また、公開する source-only top 自体の実機検証結果ではありません。raw record と counter context は `host/pause_completion_benchmark_20261012.md` にあります。25 ms と16 ms は失敗したため、成功点として掲載していません。

## ライセンスと再配布

この example 用に作成した RTL、Python、Tcl、Shell、documentation は、repository root の [`LICENSE`](LICENSE) にある MIT License（Copyright Yutaka Yasuda）で提供します。ただし repository 全体が一律 MIT ではありません。verilog-ethernet 由来ファイルは upstream MIT license と copyright notice を維持し、I350 `igb` patch は GPL-2.0-or-later/SPDX と copyright 条件を維持します。AMD generated IP とその他第三者コードは各自の条件に従い、ここには含めていません。再配布前に `DEPENDENCIES.md` を確認してください。
