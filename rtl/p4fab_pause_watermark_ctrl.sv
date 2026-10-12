module p4fab_pause_watermark_ctrl #(
  parameter int NUM_BANKS = 32,
  parameter int XOFF_OCCUPIED = 8,
  parameter int XON_OCCUPIED = 4
) (
  input logic rx_clk, input logic rx_rst,
  input logic [$clog2(NUM_BANKS+1)-1:0] free_banks,
  output logic pause_req_rx,
  input logic tx_clk, input logic tx_rst,
  output logic pause_req_tx
);
  localparam int COUNT_W = $clog2(NUM_BANKS+1);
  logic [COUNT_W-1:0] occupied_banks;
  (* ASYNC_REG = "TRUE" *) logic pause_sync_1, pause_sync_2;
  always_comb occupied_banks = NUM_BANKS-free_banks;
  always_ff @(posedge rx_clk) begin
    if (rx_rst) pause_req_rx <= 1'b0;
    else if (!pause_req_rx && occupied_banks >= XOFF_OCCUPIED) pause_req_rx <= 1'b1;
    else if (pause_req_rx && occupied_banks <= XON_OCCUPIED) pause_req_rx <= 1'b0;
  end
  always_ff @(posedge tx_clk) begin
    if (tx_rst) begin pause_sync_1<=0; pause_sync_2<=0; pause_req_tx<=0; end
    else begin pause_sync_1<=pause_req_rx; pause_sync_2<=pause_sync_1; pause_req_tx<=pause_sync_2; end
  end
  initial begin
    if (XON_OCCUPIED >= XOFF_OCCUPIED) $error("invalid PAUSE hysteresis");
    if (XOFF_OCCUPIED > NUM_BANKS) $error("XOFF exceeds NUM_BANKS");
  end
endmodule
