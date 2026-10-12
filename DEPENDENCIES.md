# Dependency and provenance audit

[日本語版](DEPENDENCIES.ja.md)

## Included

- verilog-ethernet MAC/RGMII and PAUSE control RTL, source tree `05e2_verilog_ethernet_eval/rtl`, revision expected by the 05e build scripts: `77320a9471d19c7dd383914bc049e02d9f4f1ffb`.
- Extracted bridge glue and frame-store RTL from the 05e-4a minimal cross-connect validation tree.
- KR260 dual-RGMII XDC and the implementation constraint hook.

## Deliberately excluded

- `p4fab_packet_fabric_3port`, VNP4/P4 adapters and generated VNP4 IP.
- GEM2 packet forwarding, statistics AXI datapath, PS wrapper and generated block design.
- AMD/Xilinx `.xci`, `.bd`, `.xpr`, protected IP, implementation runs, DCP, BIT, `.bit.bin`, XSA, BootFW, FIT and DTB.
- The I350 SWXOFF reference materials are included under `host/i350_swxoff/` (patches, build script, provenance/review, README, and sanitized evidence). The compiled `.ko`, kernel source tree, and build intermediates are not included.
- RC2 source, documentation, history and release artifacts.

## Buildability status

The RTL and testbench sources are organized for reuse, but this directory is not a standalone Vivado project. `standalone_pause_bridge_pl.sv` requires platform modules `kr260_pause_bridge_platform` (PS clocks/resets and MDIO/PHY) and `kr260_pause_bridge_endpoints` (the validated dual-MAC, store, watermark and CDC binding). No arbitrary-environment build claim is made.

## License review

The upstream verilog-ethernet license is copied to `docs/VERILOG_ETHERNET_LICENSE.txt`. Original RTL, Python, Tcl, Shell, and documentation authored for this example are MIT-licensed under the repository-root `LICENSE` (copyright Yutaka Yasuda). This is a mixed-license repository, not a blanket MIT relicensing: verilog-ethernet-derived files retain upstream MIT notices; I350 `igb` patch files retain their original GPL-2.0-or-later/SPDX and copyright conditions; AMD generated IP and other third-party material retain their own terms and are excluded.

## Static check

An Icarus parse/elaboration attempt parses the top and stops only on the two intentional platform modules `kr260_pause_bridge_platform` and `kr260_pause_bridge_endpoints`. A full RTL parse additionally requires Vivado-only primitives/IP (`axis_clock_converter`, `IDELAYE3`, `ODELAYE3`, `IDELAYCTRL`, `IDDR`, `ODDR`, `BUFG`, `xpm_cdc_single`). No Vivado or hardware build was run in this preparation step.
