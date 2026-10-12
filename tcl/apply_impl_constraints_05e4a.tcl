# 05e-4a dual verilog-ethernet implementation hook.
set hook_dir [file normalize [file dirname [info script]]]
set project_root [file normalize [file join $hook_dir ..]]
set build_root [expr {[info exists ::env(P4FAB_BUILD_DIR)] ? [file normalize $::env(P4FAB_BUILD_DIR)] : [file join $project_root build]}]
set reports_dir [file join $build_root reports]
set enable_j10b_temac_tx_io [expr {[info exists ::env(P4FAB_J10B_TEMAC_TX_IO)] && $::env(P4FAB_J10B_TEMAC_TX_IO) eq "1"}]
set enable_j10b_rc2_shell_loopback [expr {[info exists ::env(P4FAB_J10B_LOOPBACK_CORE_SOURCE)] && $::env(P4FAB_J10B_LOOPBACK_CORE_SOURCE) ne ""}]
file mkdir $reports_dir

set j10a_root u_port1_verilog_ethernet
set j10a_cells [get_cells -hier -quiet -filter "NAME =~ ${j10a_root}/* && (REF_NAME == IDELAYE3 || REF_NAME == ODELAYE3 || REF_NAME == IDELAYCTRL)"]
set j10a_rx_delay [filter $j10a_cells {REF_NAME == IDELAYE3}]
set j10a_txc [filter $j10a_cells {REF_NAME == ODELAYE3}]
set j10a_ctrl [filter $j10a_cells {REF_NAME == IDELAYCTRL}]
if {[llength $j10a_rx_delay] != 5 || [llength $j10a_txc] != 1 || [llength $j10a_ctrl] != 1} {
  error "J10A IODELAY primitive guard failed: rx=$j10a_rx_delay txc=$j10a_txc ctrl=$j10a_ctrl"
}
set_property IODELAY_GROUP stage1g4_rgmii_iodelay_bank65 $j10a_cells
foreach c $j10a_rx_delay { if {[get_property DELAY_VALUE $c] != 900} { error "J10A RX delay is not 900 ps: $c" } }
if {[get_property DELAY_VALUE $j10a_txc] != 250} { error "J10A TXC delay is not 250 ps" }
set j10a_bufg [get_cells -hier -quiet -filter "NAME =~ ${j10a_root}/u_rgmii_phy_if/* && REF_NAME == BUFGCE"]
if {[llength $j10a_bufg] != 1} { error "J10A RX BUFG guard failed: $j10a_bufg" }
set j10a_rx_net [get_nets -quiet -of_objects [get_pins -of_objects $j10a_bufg -filter {REF_PIN_NAME == O}]]
set_property USER_CLOCK_ROOT X1Y2 $j10a_rx_net

set j10b_xdc [file join $hook_dir .. constraints dual_rgmii_05e4a.xdc]
source $j10b_xdc
if {$enable_j10b_rc2_shell_loopback} {
  set j10b_iddr [get_cells -hier -quiet -filter {NAME =~ u_port0_verilog_ethernet/u_mac/u_mac/eth_mac_1g_rgmii_inst/rgmii_phy_if_inst/rx_ssio_ddr_inst/data_iddr_inst/iddr* && REF_NAME == IDDRE1}]
} else {
  set j10b_iddr [get_cells -hier -quiet -filter {NAME =~ u_port0_verilog_ethernet/u_rgmii_phy_if/rx_ssio_ddr_inst/data_iddr_inst/iddr* && REF_NAME == IDDRE1}]
}
if {$enable_j10b_temac_tx_io} {
  set j10b_oddr [get_cells -hier -quiet -filter {NAME =~ u_port0_verilog_ethernet/g_txc_odelay* && REF_NAME == OSERDESE3}]
} else {
  if {$enable_j10b_rc2_shell_loopback} {
    set j10b_oddr [get_cells -hier -quiet -filter {NAME =~ u_port0_verilog_ethernet/u_mac/u_mac/eth_mac_1g_rgmii_inst/rgmii_phy_if_inst/*oddr_inst/oddr* && REF_NAME == OSERDESE3}]
  } else {
    set j10b_oddr [get_cells -hier -quiet -filter {NAME =~ u_port0_verilog_ethernet/u_rgmii_phy_if/*oddr_inst/oddr* && REF_NAME == OSERDESE3}]
  }
}
if {[llength $j10b_iddr] != 5 || [llength $j10b_oddr] != 6} { error "J10B DDR primitive guard failed: IDDR=$j10b_iddr ODDR=$j10b_oddr" }
set j10b_delay [get_cells -hier -quiet -filter {NAME =~ u_port0_verilog_ethernet/* && (REF_NAME == IDELAYE3 || REF_NAME == ODELAYE3)}]
set j10b_txc_delay [get_cells -hier -quiet -filter {(NAME == u_port0_verilog_ethernet/g_txc_odelay.u_txc_odelay || NAME == u_port0_verilog_ethernet/u_txc_odelay) && REF_NAME == ODELAYE3}]
set j10b_rx_delay [filter $j10b_delay {REF_NAME == IDELAYE3}]
set j10b_delayctrl [get_cells -hier -quiet -filter {(NAME == u_port0_verilog_ethernet/g_txc_odelay.u_txc_idelayctrl || NAME == u_port0_verilog_ethernet/u_txc_idelayctrl) && REF_NAME == IDELAYCTRL}]
set expected_j10b_delay_count [expr {$enable_j10b_temac_tx_io ? 12 : 6}]
if {[llength $j10b_delay] != $expected_j10b_delay_count || [llength $j10b_txc_delay] != 1 || [llength $j10b_rx_delay] != [expr {$enable_j10b_temac_tx_io ? 6 : 5}] || [llength $j10b_delayctrl] != 1} {
  error "J10B I/O delay primitive guard failed: delay=$j10b_delay txc=$j10b_txc_delay rx=$j10b_rx_delay ctrl=$j10b_delayctrl"
}
set_property IODELAY_GROUP stage1g4_j10b_txc_iodelay_bank66 [concat $j10b_delay $j10b_delayctrl]
if {[get_property DELAY_VALUE $j10b_txc_delay] != 200 || [get_property DELAY_FORMAT $j10b_txc_delay] ne "TIME" || [get_property DELAY_TYPE $j10b_txc_delay] ne "FIXED"} {
  error "J10B TXC ODELAY configuration mismatch"
}
if {$enable_j10b_temac_tx_io} {
  set j10b_txc_cascade [get_cells -hier -quiet -filter {NAME == u_port0_verilog_ethernet/g_txc_odelay.u_txc_cascade && REF_NAME == IDELAYE3}]
  set j10b_rx_delay [filter $j10b_rx_delay {NAME != u_port0_verilog_ethernet/g_txc_odelay.u_txc_cascade}]
  set j10b_tx_data_delay [get_cells -hier -quiet -filter {NAME =~ u_port0_verilog_ethernet/g_txc_odelay.g_temac_style_txd*.u_txd_odelay || NAME == u_port0_verilog_ethernet/g_txc_odelay.u_tx_ctl_odelay}]
  if {[llength $j10b_txc_cascade] != 1 || [llength $j10b_tx_data_delay] != 5} {
    error "J10B TEMAC-style delay topology mismatch: cascade=$j10b_txc_cascade data=$j10b_tx_data_delay"
  }
}
# The accepted 05e-4a timing-clean implementation used 1000 ps. Override only
# for a documented timing exploration; do not silently fall back to 340 ps.
set j10b_rx_delay_ps [expr {[info exists ::env(P4FAB_J10B_RX_IDELAY_PS)] ? $::env(P4FAB_J10B_RX_IDELAY_PS) : 1000}]
if {$j10b_rx_delay_ps ni {100 340 600 800 900 1000 1200}} { error "Unsupported J10B RX IDELAY candidate $j10b_rx_delay_ps" }
set_property DELAY_VALUE $j10b_rx_delay_ps $j10b_rx_delay
foreach c $j10b_rx_delay {
  if {[get_property DELAY_FORMAT $c] ne "TIME" || [get_property DELAY_TYPE $c] ne "FIXED" || [get_property DELAY_VALUE $c] != $j10b_rx_delay_ps} {
    error "J10B RX IDELAY configuration mismatch: $c"
  }
}

set f [open [file join $reports_dir implementation_constraints_hook.txt] w]
puts $f "RESULT=PASS HOOK=STEPS.OPT_DESIGN.TCL.PRE"
puts $f "J10B_CONTRACT=RGMII-ID_PHY_DELAY FPGA_TXC_DELAY_PS=[get_property DELAY_VALUE $j10b_txc_delay] FPGA_RX_IDELAY_PS=$j10b_rx_delay_ps RX_IDELAY_COUNT=[llength $j10b_rx_delay] IDDR_COUNT=[llength $j10b_iddr] ODDR_COUNT=[llength $j10b_oddr] IDELAYCTRL_COUNT=[llength $j10b_delayctrl] TEMAC_STYLE_TX_IO=$enable_j10b_temac_tx_io"
puts $f "J10A_MAC=verilog-ethernet J10A_RX_IDELAY_PS=900 J10A_TXC_DELAY_PS=[get_property DELAY_VALUE $j10a_txc] J10A_IODELAY_COUNT=[llength $j10a_cells] CLOCK_ROOT=X1Y2"
close $f
