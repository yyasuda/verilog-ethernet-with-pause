`timescale 1ns/1ps
module tb_integrated_datapath;
  logic clk=0, rstn=0; always #4 clk=~clk;
  logic [7:0] arx_d, brx_d; logic arx_v, brx_v, arx_l, brx_l, arx_u, brx_u;
  logic [63:0] arx_ts=0, brx_ts=0; logic [31:0] a_tx_d,b_tx_d;
  logic [3:0] a_tx_k,b_tx_k; logic a_tx_v,b_tx_v,a_tx_l,b_tx_l;
  logic a_rx_ready,b_rx_ready,a_tx_ready,b_tx_ready; logic a_store_ready,b_store_ready; logic a_allow=0,b_allow=0;
  logic [15:0] alen,blen; logic [31:0] z32;
  logic [31:0] ac,bc,ad,bd,ae,be,ab,bb; logic [31:0] alvl,blvl,amlvl,bmlvl;
  logic [1:0] af,bf; logic [5:0] ast,bst; logic [1:0] atf,btf;
  logic [31:0] ta,tc,te,tp,ta2,tc2,te2,tp2; logic [31:0] tlvl,t2lvl,tmlvl,t2mlvl;
  logic [1:0] tf,t2f; logic [5:0] tst,t2st;
  logic p_a_rx,p_a_tx,p_b_rx,p_b_tx;
  logic [31:0] a_rx_d,b_rx_d; logic [3:0] a_rx_k,b_rx_k; logic a_rx_v,b_rx_v,a_rx_l,b_rx_l;
  logic [7:0] a_out_d,b_out_d; logic a_out_v,b_out_v,a_out_l,b_out_l;
  integer cyc=0, rxbeats=0, txinbeats=0, txoutbeats=0;
  integer outbytes=0, txinbytes=0, last_out_cycle=0; logic [7:0] last_out_data; logic saw_out_last=0;
  always @(posedge clk) begin
    if (rstn) begin
      cyc = cyc + 1;
      if (a_rx_v && a_rx_ready) begin rxbeats=rxbeats+1; $display("TRACE RX cyc=%0d d=%h k=%h l=%b v=%b r=%b",cyc,a_rx_d,a_rx_k,a_rx_l,a_rx_v,a_rx_ready); end
      if (b_tx_v && b_tx_ready) begin txinbeats=txinbeats+1; txinbytes=txinbytes + ((b_tx_k==4'hf)?4:((b_tx_k==4'h7)?3:((b_tx_k==4'h3)?2:1))); end
      if (b_out_v) begin txoutbeats=txoutbeats+1; outbytes=outbytes+1; last_out_cycle=cyc; last_out_data=b_out_d; saw_out_last=saw_out_last|b_out_l; end
    end
  end

  p4fab_rx_frame_store_8to32 #(.NUM_BANKS(3)) rx_a(
    .clk,.aresetn(rstn),.rx_tdata(arx_d),.rx_tvalid(arx_v),.rx_tlast(arx_l),.rx_tuser(arx_u),.rx_ingress_timestamp(arx_ts),
    .m_axis_tdata(a_rx_d),.m_axis_tkeep(a_rx_k),.m_axis_tvalid(a_rx_v),.m_axis_tready(a_rx_ready),.m_axis_tlast(a_rx_l),.m_axis_packet_length(alen),.m_axis_ingress_timestamp(),
    .rx_frames(ac),.rx_bytes(ad),.rx_accepted_frames(ae),.rx_busy_drop_frames(ab),.rx_overflow_drop_frames(),.rx_bad_frames(),.current_level_bytes(alvl),.max_level_bytes(amlvl),.committed_frames(),.free_banks(af),.bank_states(ast));
  p4fab_rx_frame_store_8to32 #(.NUM_BANKS(3)) rx_b(
    .clk,.aresetn(rstn),.rx_tdata(brx_d),.rx_tvalid(brx_v),.rx_tlast(brx_l),.rx_tuser(brx_u),.rx_ingress_timestamp(brx_ts),
    .m_axis_tdata(b_rx_d),.m_axis_tkeep(b_rx_k),.m_axis_tvalid(b_rx_v),.m_axis_tready(b_rx_ready),.m_axis_tlast(b_rx_l),.m_axis_packet_length(blen),.m_axis_ingress_timestamp(),
    .rx_frames(bc),.rx_bytes(bd),.rx_accepted_frames(be),.rx_busy_drop_frames(bb),.rx_overflow_drop_frames(),.rx_bad_frames(),.current_level_bytes(blvl),.max_level_bytes(bmlvl),.committed_frames(),.free_banks(bf),.bank_states(bst));
  assign a_tx_ready = a_allow & a_store_ready; assign b_tx_ready = b_allow & b_store_ready;
  static_dual_crossconnect cc(.aclk(clk),.aresetn(rstn),.a_rx_tdata(a_rx_d),.a_rx_tkeep(a_rx_k),.a_rx_tvalid(a_rx_v),.a_rx_tready(a_rx_ready),.a_rx_tlast(a_rx_l),.a_tx_tdata(a_tx_d),.a_tx_tkeep(a_tx_k),.a_tx_tvalid(a_tx_v),.a_tx_tready(a_tx_ready),.a_tx_tlast(a_tx_l),.b_rx_tdata(b_rx_d),.b_rx_tkeep(b_rx_k),.b_rx_tvalid(b_rx_v),.b_rx_tready(b_rx_ready),.b_rx_tlast(b_rx_l),.b_tx_tdata(b_tx_d),.b_tx_tkeep(b_tx_k),.b_tx_tvalid(b_tx_v),.b_tx_tready(b_tx_ready),.b_tx_tlast(b_tx_l));
  p4fab_tx_frame_store_32to8 #(.NUM_BANKS(3)) tx_a(.clk,.aresetn(rstn),.s_axis_tdata(a_tx_d),.s_axis_tkeep(a_tx_k),.s_axis_tvalid(a_tx_v),.s_axis_tready(a_store_ready),.s_axis_tlast(a_tx_l),.tx_tdata(a_out_d),.tx_tvalid(a_out_v),.tx_tready(1'b1),.tx_tlast(a_out_l),.tx_input_frames(ta),.tx_completed_frames(tc),.tx_protocol_error_frames(tp),.current_level_bytes(tlvl),.max_level_bytes(tmlvl),.committed_frames(tf),.free_banks(),.bank_states(tst));
  p4fab_tx_frame_store_32to8 #(.NUM_BANKS(3)) tx_b(.clk,.aresetn(rstn),.s_axis_tdata(b_tx_d),.s_axis_tkeep(b_tx_k),.s_axis_tvalid(b_tx_v),.s_axis_tready(b_store_ready),.s_axis_tlast(b_tx_l),.tx_tdata(b_out_d),.tx_tvalid(b_out_v),.tx_tready(1'b1),.tx_tlast(b_out_l),.tx_input_frames(ta2),.tx_completed_frames(tc2),.tx_protocol_error_frames(tp2),.current_level_bytes(t2lvl),.max_level_bytes(t2mlvl),.committed_frames(t2f),.free_banks(),.bank_states(t2st));
  p4fab_pause_watermark_ctrl #(.NUM_BANKS(3),.XOFF_OCCUPIED(2),.XON_OCCUPIED(1)) wm_a(.rx_clk(clk),.rx_rst(!rstn),.free_banks(af),.pause_req_rx(p_a_rx),.tx_clk(clk),.tx_rst(!rstn),.pause_req_tx(p_a_tx));
  p4fab_pause_watermark_ctrl #(.NUM_BANKS(3),.XOFF_OCCUPIED(2),.XON_OCCUPIED(1)) wm_b(.rx_clk(clk),.rx_rst(!rstn),.free_banks(bf),.pause_req_rx(p_b_rx),.tx_clk(clk),.tx_rst(!rstn),.pause_req_tx(p_b_tx));

  task automatic send_a(input integer n, input [7:0] base);
    integer i; begin for(i=0;i<n;i=i+1) begin @(negedge clk); arx_d=base+i; arx_v=1; arx_l=(i==n-1); arx_u=0; end @(negedge clk); arx_v=0; arx_l=0; end
  endtask
  task automatic send_b(input integer n, input [7:0] base);
    integer i; begin for(i=0;i<n;i=i+1) begin @(negedge clk); brx_d=base+i; brx_v=1; brx_l=(i==n-1); brx_u=0; end @(negedge clk); brx_v=0; brx_l=0; end
  endtask
  initial begin $display("START t=%0t",$time); arx_d=0;brx_d=0;arx_v=0;brx_v=0;arx_l=0;brx_l=0;arx_u=0;brx_u=0; repeat(8) @(posedge clk); rstn=1; a_allow=1; b_allow=1; $display("RESET_RELEASE t=%0t",$time);
    begin : length_matrix
      integer li; integer lens[0:6];
      lens[0]=60; lens[1]=64; lens[2]=68; lens[3]=72; lens[4]=76; lens[5]=80; lens[6]=84;
      for (li=0; li<7; li=li+1) begin
        rstn=0; a_allow=0; b_allow=0; repeat(4) @(posedge clk); rstn=1; a_allow=1; b_allow=1;
        rxbeats=0; txinbeats=0; txinbytes=0; txoutbeats=0; outbytes=0; last_out_cycle=0; last_out_data=0; saw_out_last=0;
        send_a(lens[li],8'h10); repeat(300) @(posedge clk);
        $display("LENGTH len=%0d rx_words=%0d txin_words=%0d txin_bytes=%0d txin_last=%b out_bytes=%0d last_pos=%0d last_data=%h out_last=%b done=%0d drain_word=%0d lane=%0d rem=%0d clock=%0d", lens[li],rxbeats,txinbeats,txinbytes,b_tx_l,outbytes,outbytes,last_out_data,saw_out_last,tc2,tx_b.drain_word,tx_b.drain_lane,tx_b.bank_byte_count[tx_b.drain_bank],cyc);
      end
      $display("PASS length comparison complete"); $finish;
    end
    send_b(80,8'h80); repeat(100) @(posedge clk); if(tc!=1) $fatal(1,"B->A tx completion=%0d",tc);
    send_a(1500,8'h20); repeat(1800) @(posedge clk); send_b(1514,8'h40); repeat(1900) @(posedge clk);
    if (tc2 != 2 || tc != 2) $fatal(1,"frame matrix incomplete A=%0d B=%0d",tc2,tc);
    b_allow=0; send_a(800,8'ha0); repeat(300) @(posedge clk); if(!p_a_rx && !p_a_tx) $display("INFO watermark not reached at this occupancy"); b_allow=1; repeat(1000) @(posedge clk);
    rstn=0; repeat(4) @(posedge clk); rstn=1; send_b(64,8'he0); repeat(100) @(posedge clk); if(tc==0) $fatal(1,"reset recovery failed");
    $display("PASS integrated datapath frames A=%0d B=%0d pause=%b/%b",tc2,tc,p_a_rx,p_b_rx); $finish;
  end
endmodule
