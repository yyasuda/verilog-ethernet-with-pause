# J10B DP83867 is configured for RGMII-ID.  TXC is edge-aligned at the FPGA
# pins; the PHY supplies both receive and transmit internal clock delays.
create_clock -name j10b_rgmii_rx_clk -period 8.000 [get_ports rgmii_rxc]
# Model the PHY launch clock separately from the clock after the FPGA input
# clock network.  This is the same source-synchronous relationship used by
# the TEMAC RGMII constraint set; constraining the pads directly against the
# propagated capture clock incorrectly charges BUFG insertion delay as board
# hold time.
create_clock -name j10b_rgmii_rx_virtual -period 8.000
# DP83867 RX internal delay places the sampling clock after the data edge.
# These are the same board/PHY timing budgets (-1/-2 ns) used by the
# validated J10A TEMAC, applied to the new direct IDDRE1 structure.
set_input_delay -clock j10b_rgmii_rx_virtual -max -1.000 [get_ports {rgmii_rxd[*] rgmii_rx_ctl}]
set_input_delay -clock j10b_rgmii_rx_virtual -min -2.000 [get_ports {rgmii_rxd[*] rgmii_rx_ctl}]
set_input_delay -clock j10b_rgmii_rx_virtual -clock_fall -max -1.000 -add_delay [get_ports {rgmii_rxd[*] rgmii_rx_ctl}]
set_input_delay -clock j10b_rgmii_rx_virtual -clock_fall -min -2.000 -add_delay [get_ports {rgmii_rxd[*] rgmii_rx_ctl}]
set_false_path -rise_from [get_clocks j10b_rgmii_rx_virtual] -fall_to [get_clocks j10b_rgmii_rx_clk] -setup
set_false_path -fall_from [get_clocks j10b_rgmii_rx_virtual] -rise_to [get_clocks j10b_rgmii_rx_clk] -setup
set_false_path -rise_from [get_clocks j10b_rgmii_rx_virtual] -rise_to [get_clocks j10b_rgmii_rx_clk] -hold
set_false_path -fall_from [get_clocks j10b_rgmii_rx_virtual] -fall_to [get_clocks j10b_rgmii_rx_clk] -hold
set_multicycle_path -from [get_clocks j10b_rgmii_rx_virtual] -to [get_clocks j10b_rgmii_rx_clk] -setup 0
set_multicycle_path -from [get_clocks j10b_rgmii_rx_virtual] -to [get_clocks j10b_rgmii_rx_clk] -hold -1
if {[info exists ::env(P4FAB_J10B_TEMAC_TX_IO)] && $::env(P4FAB_J10B_TEMAC_TX_IO) eq "1"} {
  set j10b_txc_q [get_pins -hier -quiet -filter {NAME == u_port0_verilog_ethernet/g_txc_odelay.u_temac_style_txc_oddr/OQ}]
} elseif {[info exists ::env(P4FAB_J10B_LOOPBACK_CORE_SOURCE)] && $::env(P4FAB_J10B_LOOPBACK_CORE_SOURCE) ne ""} {
  set j10b_txc_q [get_pins -hier -quiet -filter {NAME == u_port0_verilog_ethernet/u_mac/u_mac/eth_mac_1g_rgmii_inst/rgmii_phy_if_inst/clk_oddr_inst/oddr[0].oddr_inst/OQ}]
} else {
  set j10b_txc_q [get_pins -hier -quiet -filter {NAME == u_port0_verilog_ethernet/u_rgmii_phy_if/clk_oddr_inst/oddr[0].oddr_inst/OQ}]
}
if {[llength $j10b_txc_q] != 1} { error "J10B TXC ODDR Q pin missing: $j10b_txc_q" }
# DP83867 MAC-to-PHY (RGMII TX) receiver timing model.
#
# RGMIIDCTL[7:4]=6 selects a nominal 1.75 ns TX capture-clock delay.
# Model the delayed clock at the PHY capture point instead of applying the
# PHY setup/hold requirements directly to the edge-aligned TXC package pin.
# Both DDR edges are displaced by the same nominal internal delay.  Keep this
# as a generated clock sourced by the internal 125 MHz clock so Vivado retains
# the common FPGA clock path; a free-running virtual clock would incorrectly
# charge FPGA clock-tree insertion delay to the external timing budget.
create_generated_clock -name j10b_phy_tx_capture_clk \
  -source [get_pins u_clk_wiz/inst/clk_out1] \
  -edges {1 2 3} -edge_shift {1.750 1.750 1.750} [get_ports rgmii_txc]

# Conservative external budget, in ns (TI SNLA243 / DP83867):
#   delay variation  = 0.20
#   PHY I/O skew     = 0.35
#   PCB skew budget  = 0.10
#   receiver setup   = 0.50  -> max = 1.15
#   receiver hold    = 0.25  -> min = -0.90
# The variation/skew terms are included on both setup and hold and are not
# hidden with timing exceptions.  Apply the same contract to both DDR edges.
set_output_delay -clock j10b_phy_tx_capture_clk -max 1.150 [get_ports {rgmii_txd[*] rgmii_tx_ctl}]
set_output_delay -clock j10b_phy_tx_capture_clk -min -0.900 [get_ports {rgmii_txd[*] rgmii_tx_ctl}]
set_output_delay -clock j10b_phy_tx_capture_clk -clock_fall -max 1.150 -add_delay [get_ports {rgmii_txd[*] rgmii_tx_ctl}]
set_output_delay -clock j10b_phy_tx_capture_clk -clock_fall -min -0.900 -add_delay [get_ports {rgmii_txd[*] rgmii_tx_ctl}]

# J10A retains its independent bank-65 pinout and DP83867 0x0067 RGMII-ID
# configuration.  Its FPGA delay values are guarded in the implementation
# hook and deliberately do not inherit J10B's bank-66 values.
create_clock -name j10a_rgmii_rx_clk -period 8.000 [get_ports rgmii1_rxc]
create_clock -name j10a_rgmii_rx_virtual -period 8.000
set_input_delay -clock j10a_rgmii_rx_virtual -max -1.000 [get_ports {rgmii1_rxd[*] rgmii1_rx_ctl}]
set_input_delay -clock j10a_rgmii_rx_virtual -min -2.000 [get_ports {rgmii1_rxd[*] rgmii1_rx_ctl}]
set_input_delay -clock j10a_rgmii_rx_virtual -clock_fall -max -1.000 -add_delay [get_ports {rgmii1_rxd[*] rgmii1_rx_ctl}]
set_input_delay -clock j10a_rgmii_rx_virtual -clock_fall -min -2.000 -add_delay [get_ports {rgmii1_rxd[*] rgmii1_rx_ctl}]
set_false_path -rise_from [get_clocks j10a_rgmii_rx_virtual] -fall_to [get_clocks j10a_rgmii_rx_clk] -setup
set_false_path -fall_from [get_clocks j10a_rgmii_rx_virtual] -rise_to [get_clocks j10a_rgmii_rx_clk] -setup
set_false_path -rise_from [get_clocks j10a_rgmii_rx_virtual] -rise_to [get_clocks j10a_rgmii_rx_clk] -hold
set_false_path -fall_from [get_clocks j10a_rgmii_rx_virtual] -fall_to [get_clocks j10a_rgmii_rx_clk] -hold
set_multicycle_path -from [get_clocks j10a_rgmii_rx_virtual] -to [get_clocks j10a_rgmii_rx_clk] -setup 0
set_multicycle_path -from [get_clocks j10a_rgmii_rx_virtual] -to [get_clocks j10a_rgmii_rx_clk] -hold -1
create_generated_clock -name j10a_phy_tx_capture_clk \
  -source [get_pins u_clk_wiz/inst/clk_out1] \
  -edges {1 2 3} -edge_shift {1.750 1.750 1.750} [get_ports rgmii1_txc]
set_output_delay -clock j10a_phy_tx_capture_clk -max 1.150 [get_ports {rgmii1_txd[*] rgmii1_tx_ctl}]
set_output_delay -clock j10a_phy_tx_capture_clk -min -0.900 [get_ports {rgmii1_txd[*] rgmii1_tx_ctl}]
set_output_delay -clock j10a_phy_tx_capture_clk -clock_fall -max 1.150 -add_delay [get_ports {rgmii1_txd[*] rgmii1_tx_ctl}]
set_output_delay -clock j10a_phy_tx_capture_clk -clock_fall -min -0.900 -add_delay [get_ports {rgmii1_txd[*] rgmii1_tx_ctl}]
