# 依存関係と provenance 監査

[English version](DEPENDENCIES.md)

## 含まれるもの

- verilog-ethernet MAC/RGMII と PAUSE control RTL。source tree は `05e2_verilog_ethernet_eval/rtl`、05e build script が想定する revision は `77320a9471d19c7dd383914bc049e02d9f4f1ffb`。
- 05e-4a minimal cross-connect validation tree から抽出した bridge glue と frame-store RTL。
- KR260 dual-RGMII XDC と implementation constraint hook。

## 意図的に含めないもの

- `p4fab_packet_fabric_3port`、VNP4/P4 adapter、generated VNP4 IP。
- GEM2 packet forwarding、statistics AXI datapath、PS wrapper、generated block design。
- AMD/Xilinx `.xci`、`.bd`、`.xpr`、protected IP、implementation run、DCP、BIT、`.bit.bin`、XSA、BootFW、FIT、DTB。
- I350 SWXOFF reference material は `host/i350_swxoff/` に含まれます（patch、build script、provenance/review、README、匿名化 evidence）。compiled `.ko`、kernel source tree、build intermediate は含みません。
- RC2 source、documentation、history、release artifact。

## Buildability の状態

RTL と testbench source は再利用できるよう整理していますが、このディレクトリは standalone Vivado project ではありません。`standalone_pause_bridge_pl.sv` には、platform module `kr260_pause_bridge_platform`（PS clock/reset と MDIO/PHY）および `kr260_pause_bridge_endpoints`（検証済み dual-MAC、store、watermark、CDC binding）が必要です。任意環境での build は保証しません。

## ライセンス監査

upstream verilog-ethernet license は `docs/VERILOG_ETHERNET_LICENSE.txt` に収録しています。この example 用に作成した RTL、Python、Tcl、Shell、documentation は repository root の `LICENSE`（Copyright Yutaka Yasuda）に基づく MIT です。repository は一律 MIT の再ライセンスではありません。verilog-ethernet 由来ファイルは upstream MIT notice を保持し、I350 `igb` patch は元の GPL-2.0-or-later/SPDX と copyright 条件を保持します。AMD generated IP とその他第三者 material は各自の条件に従い、対象外です。

## Static check

Icarus による parse/elaboration 試行では、意図的に未提供としている `kr260_pause_bridge_platform` と `kr260_pause_bridge_endpoints` の2 module で停止します。完全な RTL parse には Vivado 専用 primitive/IP（`axis_clock_converter`、`IDELAYE3`、`ODELAYE3`、`IDELAYCTRL`、`IDDR`、`ODDR`、`BUFG`、`xpm_cdc_single`）も必要です。この準備工程では Vivado build と hardware build は実行していません。
