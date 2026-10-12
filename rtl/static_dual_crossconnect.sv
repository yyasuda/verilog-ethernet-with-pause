`timescale 1ps/1ps

// Fixed, frame-preserving two-port cross-connect.
// Both sides are assumed to be in the same clock/reset domain.  The
// RX/TX frame stores remain responsible for frame atomicity and buffering.
module static_dual_crossconnect #(
  parameter integer DATA_WIDTH = 32,
  parameter integer KEEP_WIDTH = DATA_WIDTH/8
) (
  input  wire                   aclk,
  input  wire                   aresetn,
  input  wire [DATA_WIDTH-1:0]  a_rx_tdata,
  input  wire [KEEP_WIDTH-1:0]  a_rx_tkeep,
  input  wire                   a_rx_tvalid,
  output wire                   a_rx_tready,
  input  wire                   a_rx_tlast,
  output wire [DATA_WIDTH-1:0]  a_tx_tdata,
  output wire [KEEP_WIDTH-1:0]  a_tx_tkeep,
  output wire                   a_tx_tvalid,
  input  wire                   a_tx_tready,
  output wire                   a_tx_tlast,
  input  wire [DATA_WIDTH-1:0]  b_rx_tdata,
  input  wire [KEEP_WIDTH-1:0]  b_rx_tkeep,
  input  wire                   b_rx_tvalid,
  output wire                   b_rx_tready,
  input  wire                   b_rx_tlast,
  output wire [DATA_WIDTH-1:0]  b_tx_tdata,
  output wire [KEEP_WIDTH-1:0]  b_tx_tkeep,
  output wire                   b_tx_tvalid,
  input  wire                   b_tx_tready,
  output wire                   b_tx_tlast
);
  wire unused_aclk = aclk;
  // No combinational path crosses between opposite directions.  A source
  // ready is exactly the destination ready; data/control are held by the
  // upstream frame store while valid && !ready.
  assign a_tx_tdata  = b_rx_tdata;
  assign a_tx_tkeep  = b_rx_tkeep;
  assign a_tx_tvalid = aresetn && b_rx_tvalid;
  assign a_tx_tlast  = b_rx_tlast;
  assign b_rx_tready  = aresetn && a_tx_tready;

  assign b_tx_tdata  = a_rx_tdata;
  assign b_tx_tkeep  = a_rx_tkeep;
  assign b_tx_tvalid = aresetn && a_rx_tvalid;
  assign b_tx_tlast  = a_rx_tlast;
  assign a_rx_tready  = aresetn && b_tx_tready;

endmodule
