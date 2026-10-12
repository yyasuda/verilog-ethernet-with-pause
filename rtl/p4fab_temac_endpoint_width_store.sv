module p4fab_temac_endpoint_width_store #(
  parameter integer CLOCK_CONVERTER_ID = 0,
  parameter bit USE_UNIFIED_RX_32 = 0
) (
  input  logic        global_aresetn,
  input  logic        p4fab_clk,
  input  logic        rx_mac_aclk,
  input  logic        rx_reset,
  input  logic        tx_reset,
  input  logic [7:0]  rx_axis_mac_tdata,
  input  logic        rx_axis_mac_tvalid,
  input  logic        rx_axis_mac_tlast,
  input  logic        rx_axis_mac_tuser,
  input  logic        rx_stat_mcf,
  input  logic [63:0] rx_ingress_timestamp,
  output logic [31:0] p4fab_rx_tdata,
  output logic [3:0]  p4fab_rx_tkeep,
  output logic        p4fab_rx_tvalid,
  input  logic        p4fab_rx_tready,
  output logic        p4fab_rx_tlast,
  output logic [15:0] p4fab_rx_tuser_packet_length,
  output logic [63:0] p4fab_rx_tuser_ingress_timestamp,
  input  logic [31:0] p4fab_tx_tdata,
  input  logic [3:0]  p4fab_tx_tkeep,
  input  logic        p4fab_tx_tvalid,
  output logic        p4fab_tx_tready,
  input  logic        p4fab_tx_tlast,
  output logic [7:0]  tx_axis_mac_tdata,
  output logic        tx_axis_mac_tvalid,
  input  logic        tx_axis_mac_tready,
  output logic        tx_axis_mac_tlast,
  output logic        tx_axis_mac_tuser,
  output logic        tx_lfc_req,
  output logic        p4fab_aresetn,
  output logic        rx_path_aresetn,
  output logic        tx_path_aresetn,
  output logic [31:0] rx_frames,
  output logic [31:0] rx_bytes,
  output logic [31:0] rx_accepted_frames,
  output logic [31:0] rx_busy_drop_frames,
  output logic [31:0] rx_overflow_drop_frames,
  output logic [31:0] rx_bad_frames,
  output logic [31:0] rx_current_level_bytes,
  output logic [31:0] rx_max_level_bytes,
  output logic [1:0]  rx_committed_frames,
  output logic [1:0]  rx_free_banks,
  output logic [5:0]  rx_bank_states,
  output logic [31:0] tx_input_frames,
  output logic [31:0] tx_completed_frames,
  output logic [31:0] tx_protocol_error_frames,
  output logic [31:0] tx_current_level_bytes,
  output logic [31:0] tx_max_level_bytes,
  output logic [1:0]  tx_committed_frames,
  output logic [1:0]  tx_free_banks,
  output logic [5:0]  tx_bank_states
);
  logic rx_async_aresetn, tx_async_aresetn;
  logic [31:0] rx_store_tdata, rx_cdc_tdata;
  logic [3:0] rx_store_tkeep, rx_cdc_tkeep;
  logic rx_store_tvalid, rx_store_tready, rx_store_tlast;
  logic [15:0] rx_store_packet_length;
  logic [63:0] rx_store_ingress_timestamp;
  logic [79:0] rx_store_metadata, rx_cdc_metadata;
  logic rx_cdc_tvalid, rx_cdc_tready, rx_cdc_tlast;
  logic [7:0] tx_store_tdata;
  logic tx_store_s_ready, tx_store_tvalid, tx_store_tlast;
  logic [31:0] rx_bad_frames_raw;
  logic [31:0] rx_pause_frames;
  logic [5:0] rx32_committed_frames, rx32_free_banks;
  logic [63:0] rx32_bank_states;
  logic pause_req_rx;

  assign rx_async_aresetn = global_aresetn && !rx_reset;
  assign tx_async_aresetn = global_aresetn && !tx_reset;

  p4fab_reset_sync u_p4fab_reset_sync (
    .clk(p4fab_clk), .async_aresetn(global_aresetn),
    .sync_aresetn(p4fab_aresetn));
  p4fab_reset_sync u_rx_reset_sync (
    .clk(rx_mac_aclk), .async_aresetn(rx_async_aresetn),
    .sync_aresetn(rx_path_aresetn));
  p4fab_reset_sync u_tx_reset_sync (
    .clk(p4fab_clk), .async_aresetn(tx_async_aresetn && p4fab_aresetn),
    .sync_aresetn(tx_path_aresetn));

  generate if (!USE_UNIFIED_RX_32) begin : g_rx_store_3
  p4fab_rx_frame_store_8to32 u_rx_frame_store (
    .clk(rx_mac_aclk), .aresetn(rx_path_aresetn),
    .rx_tdata(rx_axis_mac_tdata), .rx_tvalid(rx_axis_mac_tvalid),
    .rx_tlast(rx_axis_mac_tlast), .rx_tuser(rx_axis_mac_tuser),
    .rx_ingress_timestamp(rx_ingress_timestamp),
    .m_axis_tdata(rx_store_tdata), .m_axis_tkeep(rx_store_tkeep),
    .m_axis_tvalid(rx_store_tvalid), .m_axis_tready(rx_store_tready),
    .m_axis_tlast(rx_store_tlast),
    .m_axis_packet_length(rx_store_packet_length),
    .m_axis_ingress_timestamp(rx_store_ingress_timestamp),
    .rx_frames, .rx_bytes,
    .rx_accepted_frames, .rx_busy_drop_frames, .rx_overflow_drop_frames,
    .rx_bad_frames(rx_bad_frames_raw), .current_level_bytes(rx_current_level_bytes),
    .max_level_bytes(rx_max_level_bytes), .committed_frames(rx_committed_frames),
    .free_banks(rx_free_banks), .bank_states(rx_bank_states));
  assign rx_bad_frames = rx_bad_frames_raw;
  assign tx_lfc_req = 1'b0;
  end else begin : g_rx_store_32
  p4fab_rx_frame_store_8to32_unified #(.NUM_BANKS(32), .MAX_FRAME_BYTES(2048))
  u_rx_frame_store (
    .clk(rx_mac_aclk), .aresetn(rx_path_aresetn),
    .rx_tdata(rx_axis_mac_tdata), .rx_tvalid(rx_axis_mac_tvalid),
    .rx_tlast(rx_axis_mac_tlast), .rx_tuser(rx_axis_mac_tuser),
    .rx_ingress_timestamp(rx_ingress_timestamp),
    .m_axis_tdata(rx_store_tdata), .m_axis_tkeep(rx_store_tkeep),
    .m_axis_tvalid(rx_store_tvalid), .m_axis_tready(rx_store_tready),
    .m_axis_tlast(rx_store_tlast), .m_axis_packet_length(rx_store_packet_length),
    .m_axis_ingress_timestamp(rx_store_ingress_timestamp),
    .rx_frames, .rx_bytes, .rx_accepted_frames, .rx_busy_drop_frames,
    .rx_overflow_drop_frames, .rx_bad_frames(rx_bad_frames_raw),
    .current_level_bytes(rx_current_level_bytes),
    .max_level_bytes(rx_max_level_bytes), .committed_frames(rx32_committed_frames),
    .free_banks(rx32_free_banks), .bank_states(rx32_bank_states));

  // mac_ctrl_rx marks a filtered valid control frame with TUSER.  Keep that
  // frame out of the datapath, but subtract its independently qualified MCF
  // indication from the bad-frame statistic.  Bad-FCS MCFs do not assert
  // stat_rx_mcf and therefore remain errors.
  always_ff @(posedge rx_mac_aclk) begin
    if (!rx_path_aresetn) rx_pause_frames <= 0;
    else if (rx_stat_mcf) rx_pause_frames <= rx_pause_frames + 1'b1;
  end
  assign rx_bad_frames = rx_bad_frames_raw - rx_pause_frames;
  assign rx_committed_frames = (rx32_committed_frames > 3) ? 2'b11 : rx32_committed_frames[1:0];
  assign rx_free_banks = (rx32_free_banks > 3) ? 2'b11 : rx32_free_banks[1:0];
  assign rx_bank_states = rx32_bank_states[5:0];
  p4fab_pause_watermark_ctrl #(
    .NUM_BANKS(32), .XOFF_OCCUPIED(8), .XON_OCCUPIED(4)
  ) u_pause_watermark (
    .rx_clk(rx_mac_aclk), .rx_rst(!rx_path_aresetn), .free_banks(rx32_free_banks),
    .pause_req_rx(pause_req_rx), .tx_clk(p4fab_clk),
    .tx_rst(!tx_path_aresetn), .pause_req_tx(tx_lfc_req));
  end endgenerate

  assign rx_store_metadata = {rx_store_ingress_timestamp,
                              rx_store_packet_length};

  generate if (CLOCK_CONVERTER_ID == 0) begin : g_clock_converter_0
  axis_clock_converter_03m_rx u_rx_clock_converter (
    .s_axis_aresetn(rx_path_aresetn), .s_axis_aclk(rx_mac_aclk),
    .s_axis_tvalid(rx_store_tvalid), .s_axis_tready(rx_store_tready),
    .s_axis_tdata(rx_store_tdata), .s_axis_tkeep(rx_store_tkeep),
    .s_axis_tlast(rx_store_tlast), .s_axis_tuser(rx_store_metadata),
    .m_axis_aresetn(p4fab_aresetn),
    .m_axis_aclk(p4fab_clk), .m_axis_tvalid(rx_cdc_tvalid),
    .m_axis_tready(rx_cdc_tready), .m_axis_tdata(rx_cdc_tdata),
    .m_axis_tkeep(rx_cdc_tkeep), .m_axis_tlast(rx_cdc_tlast),
    .m_axis_tuser(rx_cdc_metadata));
  end else begin : g_clock_converter_1
  axis_clock_converter_03p_rx1 u_rx_clock_converter (
    .s_axis_aresetn(rx_path_aresetn), .s_axis_aclk(rx_mac_aclk),
    .s_axis_tvalid(rx_store_tvalid), .s_axis_tready(rx_store_tready),
    .s_axis_tdata(rx_store_tdata), .s_axis_tkeep(rx_store_tkeep),
    .s_axis_tlast(rx_store_tlast), .s_axis_tuser(rx_store_metadata),
    .m_axis_aresetn(p4fab_aresetn),
    .m_axis_aclk(p4fab_clk), .m_axis_tvalid(rx_cdc_tvalid),
    .m_axis_tready(rx_cdc_tready), .m_axis_tdata(rx_cdc_tdata),
    .m_axis_tkeep(rx_cdc_tkeep), .m_axis_tlast(rx_cdc_tlast),
    .m_axis_tuser(rx_cdc_metadata));
  end endgenerate

  assign p4fab_rx_tdata  = rx_cdc_tdata;
  assign p4fab_rx_tkeep  = rx_cdc_tkeep;
  assign p4fab_rx_tlast  = rx_cdc_tlast;
  assign p4fab_rx_tuser_packet_length = rx_cdc_metadata[15:0];
  assign p4fab_rx_tuser_ingress_timestamp = rx_cdc_metadata[79:16];
  assign p4fab_rx_tvalid = p4fab_aresetn && rx_cdc_tvalid;
  assign rx_cdc_tready   = p4fab_aresetn && p4fab_rx_tready;

  p4fab_tx_frame_store_32to8 u_tx_frame_store (
    .clk(p4fab_clk), .aresetn(tx_path_aresetn),
    .s_axis_tdata(p4fab_tx_tdata), .s_axis_tkeep(p4fab_tx_tkeep),
    .s_axis_tvalid(p4fab_tx_tvalid && tx_path_aresetn),
    .s_axis_tready(tx_store_s_ready), .s_axis_tlast(p4fab_tx_tlast),
    .tx_tdata(tx_store_tdata), .tx_tvalid(tx_store_tvalid),
    .tx_tready(tx_axis_mac_tready && tx_path_aresetn),
    .tx_tlast(tx_store_tlast), .tx_input_frames, .tx_completed_frames,
    .tx_protocol_error_frames, .current_level_bytes(tx_current_level_bytes),
    .max_level_bytes(tx_max_level_bytes), .committed_frames(tx_committed_frames),
    .free_banks(tx_free_banks), .bank_states(tx_bank_states));

  assign p4fab_tx_tready    = tx_path_aresetn && tx_store_s_ready;
  assign tx_axis_mac_tdata  = tx_store_tdata;
  assign tx_axis_mac_tvalid = tx_path_aresetn && tx_store_tvalid;
  assign tx_axis_mac_tlast  = tx_path_aresetn && tx_store_tlast;
  assign tx_axis_mac_tuser  = 1'b0;
endmodule
