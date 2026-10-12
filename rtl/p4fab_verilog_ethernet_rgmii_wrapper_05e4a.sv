// 05e-4a common production wrapper around upstream verilog-ethernet.
// The DP83867 is configured for RGMII-ID, so TXC is forwarded edge-aligned;
// the PHY supplies the board-interface clock delay.
module p4fab_verilog_ethernet_rgmii_wrapper #(
  parameter TARGET = "XILINX",
  parameter integer RX_IDELAY_PS = 340,
  parameter integer TXC_ODELAY_PS = 200,
  parameter [47:0] PAUSE_SOURCE_MAC = 48'h020000000001
) (
  input  wire gtx_clk,
  input  wire refclk,
  input  wire glbl_rstn,
  input  wire tx_lfc_req,
  output wire [7:0] rx_axis_mac_tdata,
  output wire rx_axis_mac_tvalid,
  output wire rx_axis_mac_tlast,
  output wire rx_axis_mac_tuser,
  output wire rx_mac_aclk,
  output wire rx_reset,
  input  wire [7:0] tx_axis_mac_tdata,
  input  wire tx_axis_mac_tvalid,
  input  wire tx_axis_mac_tlast,
  input  wire tx_axis_mac_tuser,
  output wire tx_axis_mac_tready,
  output wire tx_mac_aclk,
  output wire tx_reset,
  output wire stat_rx_mcf,
  output wire stat_rx_lfc_pkt,
  output wire stat_rx_lfc_xon,
  output wire stat_rx_lfc_xoff,
  output wire stat_tx_lfc_pkt,
  output wire stat_tx_lfc_xon,
  output wire stat_tx_lfc_xoff,
  output wire [31:0] debug_tx,
  output wire [3:0] rgmii_txd,
  output wire rgmii_tx_ctl,
  output wire rgmii_txc,
  input  wire [3:0] rgmii_rxd,
  input  wire rgmii_rx_ctl,
  input  wire rgmii_rxc
);
  wire [7:0] gmii_rxd, gmii_txd;
  wire gmii_rx_dv, gmii_rx_er, gmii_tx_en, gmii_tx_er;
  wire tx_clk_enable;
  wire tx_start_packet;
  wire tx_error_underflow;
  wire idelayctrl_ready_debug;
  wire rx_lfc_req;
  wire rgmii_txc_raw;
  wire [3:0] rgmii_txd_phyif;
  wire rgmii_tx_ctl_phyif;
  wire [3:0] rgmii_rxd_delayed;
  wire rgmii_rx_ctl_delayed;

  rgmii_phy_if #(
    .TARGET(TARGET), .IODDR_STYLE("IODDR"),
    .CLOCK_INPUT_STYLE("BUFG"), .USE_CLK90("FALSE")
  ) u_rgmii_phy_if (
    .clk(gtx_clk), .clk90(gtx_clk), .rst(!glbl_rstn),
    .mac_gmii_rx_clk(rx_mac_aclk), .mac_gmii_rx_rst(rx_reset),
    .mac_gmii_rxd(gmii_rxd), .mac_gmii_rx_dv(gmii_rx_dv),
    .mac_gmii_rx_er(gmii_rx_er), .mac_gmii_tx_clk(tx_mac_aclk),
    .mac_gmii_tx_rst(tx_reset), .mac_gmii_tx_clk_en(tx_clk_enable),
    .mac_gmii_txd(gmii_txd), .mac_gmii_tx_en(gmii_tx_en),
    .mac_gmii_tx_er(gmii_tx_er), .phy_rgmii_rx_clk(rgmii_rxc),
    .phy_rgmii_rxd(rgmii_rxd_delayed), .phy_rgmii_rx_ctl(rgmii_rx_ctl_delayed),
    .phy_rgmii_tx_clk(rgmii_txc_raw), .phy_rgmii_txd(rgmii_txd_phyif),
    .phy_rgmii_tx_ctl(rgmii_tx_ctl_phyif), .speed(2'b10));

  // P4FAB_J10B_DISABLE_PAUSE is a historical diagnostic-only macro.
  // It is normally undefined, so the J10B MAC PAUSE datapath remains enabled.
  // The I350 SWXOFF reference driver does not control this FPGA-side setting.
  // The endpoint, TX frame store, clocks, resets, and physical I/O are
  // unchanged in either build.
`ifdef P4FAB_J10B_DISABLE_PAUSE
  localparam J10B_PAUSE_ENABLE = 0;
`else
  localparam J10B_PAUSE_ENABLE = 1;
`endif

  eth_mac_1g #(
    .DATA_WIDTH(8), .ENABLE_PADDING(1), .MIN_FRAME_LENGTH(64),
    .PTP_TS_ENABLE(0), .PFC_ENABLE(0), .PAUSE_ENABLE(J10B_PAUSE_ENABLE)
  ) u_mac (
    .rx_clk(rx_mac_aclk), .rx_rst(rx_reset),
    .tx_clk(tx_mac_aclk), .tx_rst(tx_reset),
    .tx_axis_tdata(tx_axis_mac_tdata), .tx_axis_tvalid(tx_axis_mac_tvalid),
    .tx_axis_tready(tx_axis_mac_tready), .tx_axis_tlast(tx_axis_mac_tlast),
    .tx_axis_tuser(tx_axis_mac_tuser),
    .rx_axis_tdata(rx_axis_mac_tdata), .rx_axis_tvalid(rx_axis_mac_tvalid),
    .rx_axis_tlast(rx_axis_mac_tlast), .rx_axis_tuser(rx_axis_mac_tuser),
    .gmii_rxd(gmii_rxd), .gmii_rx_dv(gmii_rx_dv), .gmii_rx_er(gmii_rx_er),
    .gmii_txd(gmii_txd), .gmii_tx_en(gmii_tx_en), .gmii_tx_er(gmii_tx_er),
    .tx_ptp_ts(96'b0), .rx_ptp_ts(96'b0), .tx_axis_ptp_ts(),
    .tx_axis_ptp_ts_tag(), .tx_axis_ptp_ts_valid(),
    .tx_lfc_req(tx_lfc_req), .tx_lfc_resend(1'b0),
    .rx_lfc_en(1'b1), .rx_lfc_req(rx_lfc_req), .rx_lfc_ack(1'b0),
    .tx_pfc_req(8'b0), .tx_pfc_resend(1'b0), .rx_pfc_en(8'b0),
    .rx_pfc_req(), .rx_pfc_ack(8'b0),
    .tx_lfc_pause_en(1'b1), .tx_pause_req(1'b0), .tx_pause_ack(),
    .rx_clk_enable(1'b1), .tx_clk_enable(tx_clk_enable),
    .rx_mii_select(1'b0), .tx_mii_select(1'b0),
    .tx_start_packet(tx_start_packet), .tx_error_underflow(tx_error_underflow), .rx_start_packet(),
    .rx_error_bad_frame(), .rx_error_bad_fcs(), .stat_tx_mcf(),
    .stat_rx_mcf(stat_rx_mcf), .stat_tx_lfc_pkt(stat_tx_lfc_pkt),
    .stat_tx_lfc_xon(stat_tx_lfc_xon), .stat_tx_lfc_xoff(stat_tx_lfc_xoff),
    .stat_tx_lfc_paused(), .stat_tx_pfc_pkt(), .stat_tx_pfc_xon(),
    .stat_tx_pfc_xoff(), .stat_tx_pfc_paused(),
    .stat_rx_lfc_pkt(stat_rx_lfc_pkt), .stat_rx_lfc_xon(stat_rx_lfc_xon),
    .stat_rx_lfc_xoff(stat_rx_lfc_xoff), .stat_rx_lfc_paused(),
    .stat_rx_pfc_pkt(), .stat_rx_pfc_xon(), .stat_rx_pfc_xoff(),
    .stat_rx_pfc_paused(), .cfg_ifg(8'd12),
    .cfg_tx_enable(1'b1), .cfg_rx_enable(1'b1),
    .cfg_mcf_rx_eth_dst_mcast(48'h0180c2000001),
    .cfg_mcf_rx_check_eth_dst_mcast(1'b1),
    .cfg_mcf_rx_eth_dst_ucast(48'b0), .cfg_mcf_rx_check_eth_dst_ucast(1'b0),
    .cfg_mcf_rx_eth_src(48'b0), .cfg_mcf_rx_check_eth_src(1'b0),
    .cfg_mcf_rx_eth_type(16'h8808), .cfg_mcf_rx_opcode_lfc(16'h0001),
    .cfg_mcf_rx_check_opcode_lfc(1'b1), .cfg_mcf_rx_opcode_pfc(16'h0101),
    .cfg_mcf_rx_check_opcode_pfc(1'b0), .cfg_mcf_rx_forward(1'b0),
    .cfg_mcf_rx_enable(1'b1), .cfg_tx_lfc_eth_dst(48'h0180c2000001),
    .cfg_tx_lfc_eth_src(PAUSE_SOURCE_MAC), .cfg_tx_lfc_eth_type(16'h8808),
    .cfg_tx_lfc_opcode(16'h0001), .cfg_tx_lfc_en(1'b1),
    .cfg_tx_lfc_quanta(16'd64), .cfg_tx_lfc_refresh(16'd32),
    .cfg_tx_pfc_eth_dst(48'b0), .cfg_tx_pfc_eth_src(48'b0),
    .cfg_tx_pfc_eth_type(16'b0), .cfg_tx_pfc_opcode(16'b0),
    .cfg_tx_pfc_en(1'b0), .cfg_tx_pfc_quanta(128'b0),
    .cfg_tx_pfc_refresh(128'b0), .cfg_rx_lfc_opcode(16'h0001),
    .cfg_rx_lfc_en(1'b1), .cfg_rx_pfc_opcode(16'h0101), .cfg_rx_pfc_en(1'b0));

  generate
    if (TARGET == "XILINX") begin : g_txc_odelay
      // The first routed 1100 ps calibration run measured 1.210 ns
      // (setup corner) / 1.331 ns (hold corner) through ODELAYE3.  Its
      // +1.013/-0.753 ns slacks put the balanced programmed value near
      // 217 ps; use 200 ps to retain margin at both process corners.
      reg [5:0] idelayctrl_reset_count = 6'd0;
      reg idelayctrl_reset = 1'b1;
      wire refclk_resetn_sync;

      xpm_cdc_single #(
        .DEST_SYNC_FF(2), .INIT_SYNC_FF(1), .SIM_ASSERT_CHK(1),
        .SRC_INPUT_REG(0)
      ) u_refclk_resetn_sync (
        .dest_out(refclk_resetn_sync), .dest_clk(refclk),
        .src_clk(1'b0), .src_in(glbl_rstn));

      always @(posedge refclk) begin
        if (!refclk_resetn_sync) begin
          idelayctrl_reset_count <= 6'd0;
          idelayctrl_reset <= 1'b1;
        end else if (idelayctrl_reset_count < 6'd32) begin
          idelayctrl_reset_count <= idelayctrl_reset_count + 1'b1;
          idelayctrl_reset <= 1'b1;
        end else begin
          idelayctrl_reset <= 1'b0;
        end
      end

      (* IODELAY_GROUP = "stage1g4_j10b_txc_iodelay_bank66" *)
      IDELAYCTRL #(.SIM_DEVICE("ULTRASCALE_PLUS")) u_txc_idelayctrl (
        .RDY(idelayctrl_ready_debug), .REFCLK(refclk), .RST(idelayctrl_reset));

`ifdef P4FAB_J10B_TEMAC_TX_IO
      // 05e-3d-11 diagnostic variant: reproduce the validated TEMAC TX I/O
      // topology without changing the MAC, frame store, PHY setup, or RX path.
      wire txc_oddr;
      wire txc_cascade_out;
      wire txc_cascade_return;
      wire [3:0] txd_oddr;
      wire [3:0] txd_delayed;
      wire tx_ctl_oddr;
      wire tx_ctl_delayed;

      ODDRE1 #(.SRVAL(1'b0)) u_temac_style_txc_oddr (
        .Q(txc_oddr), .C(gtx_clk), .D1(1'b1), .D2(1'b0),
        .SR(!glbl_rstn));

      for (genvar t = 0; t < 4; t = t+1) begin : g_temac_style_txd
        ODDRE1 #(.SRVAL(1'b0)) u_txd_oddr (
          .Q(txd_oddr[t]), .C(gtx_clk), .D1(gmii_txd[t]),
          .D2(gmii_txd[t+4]), .SR(!glbl_rstn));
        (* IODELAY_GROUP = "stage1g4_j10b_txc_iodelay_bank66" *)
        ODELAYE3 #(
          .CASCADE("NONE"), .DELAY_FORMAT("TIME"), .DELAY_TYPE("FIXED"),
          .DELAY_VALUE(0), .REFCLK_FREQUENCY(333.333),
          .SIM_DEVICE("ULTRASCALE_PLUS"), .UPDATE_MODE("ASYNC")
        ) u_txd_odelay (
          .CASC_OUT(), .CNTVALUEOUT(), .DATAOUT(txd_delayed[t]),
          .CASC_IN(1'b0), .CASC_RETURN(1'b0), .CE(1'b0), .CLK(1'b0),
          .CNTVALUEIN(9'd0), .EN_VTC(1'b1), .INC(1'b0), .LOAD(1'b0),
          .ODATAIN(txd_oddr[t]), .RST(1'b0));
      end

      ODDRE1 #(.SRVAL(1'b0)) u_temac_style_tx_ctl_oddr (
        .Q(tx_ctl_oddr), .C(gtx_clk), .D1(gmii_tx_en),
        .D2(gmii_tx_en ^ gmii_tx_er), .SR(!glbl_rstn));
      (* IODELAY_GROUP = "stage1g4_j10b_txc_iodelay_bank66" *)
      ODELAYE3 #(
        .CASCADE("NONE"), .DELAY_FORMAT("TIME"), .DELAY_TYPE("FIXED"),
        .DELAY_VALUE(0), .REFCLK_FREQUENCY(333.333),
        .SIM_DEVICE("ULTRASCALE_PLUS"), .UPDATE_MODE("ASYNC")
      ) u_tx_ctl_odelay (
        .CASC_OUT(), .CNTVALUEOUT(), .DATAOUT(tx_ctl_delayed),
        .CASC_IN(1'b0), .CASC_RETURN(1'b0), .CE(1'b0), .CLK(1'b0),
        .CNTVALUEIN(9'd0), .EN_VTC(1'b1), .INC(1'b0), .LOAD(1'b0),
        .ODATAIN(tx_ctl_oddr), .RST(1'b0));

      (* IODELAY_GROUP = "stage1g4_j10b_txc_iodelay_bank66" *)
      ODELAYE3 #(
        .CASCADE("MASTER"), .DELAY_FORMAT("TIME"), .DELAY_TYPE("FIXED"),
          .DELAY_VALUE(TXC_ODELAY_PS), .REFCLK_FREQUENCY(333.333),
        .SIM_DEVICE("ULTRASCALE_PLUS"), .UPDATE_MODE("ASYNC")
      ) u_txc_odelay (
        .CASC_OUT(txc_cascade_out), .CNTVALUEOUT(), .DATAOUT(rgmii_txc),
        .CASC_IN(1'b0), .CASC_RETURN(txc_cascade_return), .CE(1'b0), .CLK(1'b0),
        .CNTVALUEIN(9'd0), .EN_VTC(1'b1), .INC(1'b0), .LOAD(1'b0),
        .ODATAIN(txc_oddr), .RST(1'b0));
      (* IODELAY_GROUP = "stage1g4_j10b_txc_iodelay_bank66" *)
      IDELAYE3 #(
        .CASCADE("SLAVE_END"), .DELAY_FORMAT("TIME"), .DELAY_SRC("DATAIN"),
        .DELAY_TYPE("FIXED"), .DELAY_VALUE(0),
        .REFCLK_FREQUENCY(333.333), .SIM_DEVICE("ULTRASCALE_PLUS"),
        .UPDATE_MODE("ASYNC")
      ) u_txc_cascade (
        .CASC_OUT(), .CNTVALUEOUT(), .DATAOUT(txc_cascade_return),
        .CASC_IN(txc_cascade_out), .CASC_RETURN(1'b0), .CE(1'b0), .CLK(1'b0),
        .CNTVALUEIN(9'd0), .DATAIN(1'b0), .EN_VTC(1'b1),
        .IDATAIN(1'b0), .INC(1'b0), .LOAD(1'b0), .RST(1'b0));

      assign rgmii_txd = txd_delayed;
      assign rgmii_tx_ctl = tx_ctl_delayed;
`else
      assign rgmii_txd = rgmii_txd_phyif;
      assign rgmii_tx_ctl = rgmii_tx_ctl_phyif;

      (* IODELAY_GROUP = "stage1g4_j10b_txc_iodelay_bank66" *)
      ODELAYE3 #(
        .CASCADE("NONE"), .DELAY_FORMAT("TIME"), .DELAY_TYPE("FIXED"),
          .DELAY_VALUE(TXC_ODELAY_PS), .REFCLK_FREQUENCY(333.333),
        .SIM_DEVICE("ULTRASCALE_PLUS"), .UPDATE_MODE("ASYNC")
      ) u_txc_odelay (
        .CASC_OUT(), .CNTVALUEOUT(), .DATAOUT(rgmii_txc),
        .CASC_IN(1'b0), .CASC_RETURN(1'b0), .CE(1'b0), .CLK(1'b0),
        .CNTVALUEIN(9'd0), .EN_VTC(1'b1), .INC(1'b0), .LOAD(1'b0),
        .ODATAIN(rgmii_txc_raw), .RST(1'b0));
`endif

      for (genvar n = 0; n < 4; n = n+1) begin : g_rxd_idelay
        (* IODELAY_GROUP = "stage1g4_j10b_txc_iodelay_bank66" *)
        IDELAYE3 #(
          .CASCADE("NONE"), .DELAY_FORMAT("TIME"), .DELAY_SRC("IDATAIN"),
          .DELAY_TYPE("FIXED"), .DELAY_VALUE(RX_IDELAY_PS),
          .REFCLK_FREQUENCY(333.333), .SIM_DEVICE("ULTRASCALE_PLUS"),
          .UPDATE_MODE("ASYNC")
        ) u_rxd_idelay (
          .CASC_OUT(), .CNTVALUEOUT(), .DATAOUT(rgmii_rxd_delayed[n]),
          .CASC_IN(1'b0), .CASC_RETURN(1'b0), .CE(1'b0), .CLK(1'b0),
          .CNTVALUEIN(9'd0), .DATAIN(1'b0), .EN_VTC(1'b1),
          .IDATAIN(rgmii_rxd[n]), .INC(1'b0), .LOAD(1'b0), .RST(1'b0));
      end

      (* IODELAY_GROUP = "stage1g4_j10b_txc_iodelay_bank66" *)
      IDELAYE3 #(
        .CASCADE("NONE"), .DELAY_FORMAT("TIME"), .DELAY_SRC("IDATAIN"),
        .DELAY_TYPE("FIXED"), .DELAY_VALUE(RX_IDELAY_PS),
        .REFCLK_FREQUENCY(333.333), .SIM_DEVICE("ULTRASCALE_PLUS"),
        .UPDATE_MODE("ASYNC")
      ) u_rx_ctl_idelay (
        .CASC_OUT(), .CNTVALUEOUT(), .DATAOUT(rgmii_rx_ctl_delayed),
        .CASC_IN(1'b0), .CASC_RETURN(1'b0), .CE(1'b0), .CLK(1'b0),
        .CNTVALUEIN(9'd0), .DATAIN(1'b0), .EN_VTC(1'b1),
        .IDATAIN(rgmii_rx_ctl), .INC(1'b0), .LOAD(1'b0), .RST(1'b0));
    end else begin : g_txc_no_odelay
      assign rgmii_txc = rgmii_txc_raw;
      assign rgmii_txd = rgmii_txd_phyif;
      assign rgmii_tx_ctl = rgmii_tx_ctl_phyif;
      assign rgmii_rxd_delayed = rgmii_rxd;
      assign rgmii_rx_ctl_delayed = rgmii_rx_ctl;
      assign idelayctrl_ready_debug = 1'b1;
    end
  endgenerate

  // Passive 05e-3d-8 diagnostic tap.  Bits [24:15] are the values presented
  // to the RGMII output DDR registers, before package-pin timing effects.
  assign debug_tx = {
    6'b0, glbl_rstn,
    (gmii_tx_en ^ gmii_tx_er), gmii_tx_en,
    gmii_txd[7:4], gmii_txd[3:0],
    idelayctrl_ready_debug, tx_reset, tx_clk_enable,
    tx_error_underflow, tx_start_packet,
    gmii_tx_er, gmii_tx_en, gmii_txd
  };
endmodule
