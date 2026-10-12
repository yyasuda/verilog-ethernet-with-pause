`timescale 1ns/1ps
module tb_static_dual_crossconnect;
  reg clk=0, rstn=0; always #4 clk=~clk;
  reg [31:0] ar_d, br_d; reg [3:0] ar_k, br_k; reg ar_v=0, br_v=0, ar_l=0, br_l=0;
  wire ar_r, br_r; wire [31:0] at_d, bt_d; wire [3:0] at_k, bt_k;
  wire at_v, bt_v, at_l, bt_l; reg at_r=1, bt_r=1;
  integer a_count=0, b_count=0, errors=0;
  static_dual_crossconnect dut(.aclk(clk),.aresetn(rstn),
    .a_rx_tdata(ar_d),.a_rx_tkeep(ar_k),.a_rx_tvalid(ar_v),.a_rx_tready(ar_r),.a_rx_tlast(ar_l),
    .a_tx_tdata(at_d),.a_tx_tkeep(at_k),.a_tx_tvalid(at_v),.a_tx_tready(at_r),.a_tx_tlast(at_l),
    .b_rx_tdata(br_d),.b_rx_tkeep(br_k),.b_rx_tvalid(br_v),.b_rx_tready(br_r),.b_rx_tlast(br_l),
    .b_tx_tdata(bt_d),.b_tx_tkeep(bt_k),.b_tx_tvalid(bt_v),.b_tx_tready(bt_r),.b_tx_tlast(bt_l));
  always @(posedge clk) begin
    if (rstn) begin
      if (at_v && at_r) begin if (at_d !== (32'hb000 + b_count)) errors=errors+1; b_count=b_count+1; end
      if (bt_v && bt_r) begin if (bt_d !== (32'ha000 + a_count)) errors=errors+1; a_count=a_count+1; end
    end
  end
  initial begin
    ar_d=0; ar_k=4'hf; ar_l=0; br_d=0; br_k=4'hf; br_l=0;
    repeat(3) @(posedge clk); rstn=1;
    // simultaneous two-beat frames, with a one-cycle backpressure gap
    @(negedge clk); ar_v=1; ar_d=32'ha000; ar_l=0; br_v=1; br_d=32'hb000; br_l=0;
    @(negedge clk); ar_d=32'ha001; ar_l=1; br_d=32'hb001; br_l=1;
    @(negedge clk); ar_v=0; br_v=0; at_r=0; bt_r=0;
    @(negedge clk); at_r=1; bt_r=1;
    repeat(3) @(posedge clk);
    if (a_count != 2 || b_count != 2 || errors != 0) begin
      $display("FAIL a=%0d b=%0d errors=%0d",a_count,b_count,errors); $fatal;
    end
    $display("PASS static dual cross-connect a=%0d b=%0d",a_count,b_count);
    $finish;
  end
endmodule
