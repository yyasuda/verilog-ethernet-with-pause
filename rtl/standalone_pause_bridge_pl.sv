// Source-only PL top contract.  The board wrapper supplies gtx/ref clocks,
// reset, MDIO/PHY reset and the existing AXIS CDC/IP boundary.  The packet
// datapath contains only the two validated endpoint stores and fixed cross-connect.
module standalone_pause_bridge_pl (
  input wire som240_clk,
  output wire [3:0] j10a_rgmii_txd, output wire j10a_rgmii_tx_ctl, output wire j10a_rgmii_txc,
  input wire [3:0] j10a_rgmii_rxd, input wire j10a_rgmii_rx_ctl, input wire j10a_rgmii_rxc,
  output wire [3:0] j10b_rgmii_txd, output wire j10b_rgmii_tx_ctl, output wire j10b_rgmii_txc,
  input wire [3:0] j10b_rgmii_rxd, input wire j10b_rgmii_rx_ctl, input wire j10b_rgmii_rxc,
  output wire j10a_phy_reset_n, output wire j10a_phy_mdc, inout wire j10a_phy_mdio,
  output wire j10b_phy_reset_n, output wire j10b_phy_mdc, inout wire j10b_phy_mdio
);
  // `kr260_pause_bridge_platform` is the documented PS/clock/MDIO platform
  // prerequisite. It has no packet AXIS path and is not distributed here.
  wire gtx_clk, refclk, resetn;
  wire [1:0] phy_reset_n, phy_mdc; wire [1:0] phy_mdio;
  kr260_pause_bridge_platform platform (.som240_clk(som240_clk), .gtx_clk(gtx_clk), .refclk(refclk), .resetn(resetn), .phy_reset_n(phy_reset_n), .phy_mdc(phy_mdc), .phy_mdio(phy_mdio));
  assign j10a_phy_reset_n=phy_reset_n[0]; assign j10b_phy_reset_n=phy_reset_n[1];
  assign j10a_phy_mdc=phy_mdc[0]; assign j10b_phy_mdc=phy_mdc[1];
  // MDIO is intentionally not a completed bidirectional implementation here:
  // these assigns are only the platform boundary contract. The platform
  // wrapper must provide the actual I/O buffers, tri-state direction and
  // Clause-22 masters before hardware use.
  assign phy_mdio[0]=j10a_phy_mdio; assign phy_mdio[1]=j10b_phy_mdio;
  // The validated endpoint wrapper owns RX/TX stores, AXIS clock converters,
  // watermark PAUSE requests, and reset/CDC. The two AXIS pairs below are the
  // exact interface used by stage1g4_hw_top_05e4a_cc.sv.
  wire [31:0] a_rx_data,b_rx_data,a_tx_data,b_tx_data; wire [3:0] a_rx_keep,b_rx_keep,a_tx_keep,b_tx_keep;
  wire a_rx_valid,b_rx_valid,a_tx_valid,b_tx_valid,a_rx_ready,b_rx_ready,a_tx_ready,b_tx_ready,a_rx_last,b_rx_last,a_tx_last,b_tx_last;
  static_dual_crossconnect u_cross (.aclk(gtx_clk),.aresetn(resetn),.a_rx_tdata(a_rx_data),.a_rx_tkeep(a_rx_keep),.a_rx_tvalid(a_rx_valid),.a_rx_tready(a_rx_ready),.a_rx_tlast(a_rx_last),.a_tx_tdata(a_tx_data),.a_tx_tkeep(a_tx_keep),.a_tx_tvalid(a_tx_valid),.a_tx_tready(a_tx_ready),.a_tx_tlast(a_tx_last),.b_rx_tdata(b_rx_data),.b_rx_tkeep(b_rx_keep),.b_rx_tvalid(b_rx_valid),.b_rx_tready(b_rx_ready),.b_rx_tlast(b_rx_last),.b_tx_tdata(b_tx_data),.b_tx_tkeep(b_tx_keep),.b_tx_tvalid(b_tx_valid),.b_tx_tready(b_tx_ready),.b_tx_tlast(b_tx_last));
  // Platform endpoint instances bind the signals above to the two MACs.
  // Keeping this binding external avoids distributing PS/generated IP.
  kr260_pause_bridge_endpoints endpoints (.gtx_clk(gtx_clk),.refclk(refclk),.resetn(resetn),.a_rgmii_txd(j10a_rgmii_txd),.a_rgmii_tx_ctl(j10a_rgmii_tx_ctl),.a_rgmii_txc(j10a_rgmii_txc),.a_rgmii_rxd(j10a_rgmii_rxd),.a_rgmii_rx_ctl(j10a_rgmii_rx_ctl),.a_rgmii_rxc(j10a_rgmii_rxc),.b_rgmii_txd(j10b_rgmii_txd),.b_rgmii_tx_ctl(j10b_rgmii_tx_ctl),.b_rgmii_txc(j10b_rgmii_txc),.b_rgmii_rxd(j10b_rgmii_rxd),.b_rgmii_rx_ctl(j10b_rgmii_rx_ctl),.b_rgmii_rxc(j10b_rgmii_rxc),.a_rx_tdata(a_rx_data),.a_rx_tkeep(a_rx_keep),.a_rx_tvalid(a_rx_valid),.a_rx_tready(a_rx_ready),.a_rx_tlast(a_rx_last),.a_tx_tdata(a_tx_data),.a_tx_tkeep(a_tx_keep),.a_tx_tvalid(a_tx_valid),.a_tx_tready(a_tx_ready),.a_tx_tlast(a_tx_last),.b_rx_tdata(b_rx_data),.b_rx_tkeep(b_rx_keep),.b_rx_tvalid(b_rx_valid),.b_rx_tready(b_rx_ready),.b_rx_tlast(b_rx_last),.b_tx_tdata(b_tx_data),.b_tx_tkeep(b_tx_keep),.b_tx_tvalid(b_tx_valid),.b_tx_tready(b_tx_ready),.b_tx_tlast(b_tx_last));
endmodule
