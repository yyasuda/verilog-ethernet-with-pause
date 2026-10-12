// One fixed frame bank, expressed as the Vivado simple-dual-port RAM
// inference template: one synchronous write port and one synchronous read
// port on a common clock.  RAM contents and the read-data register are not
// reset; bank ownership prevents stale data from becoming visible.
module p4fab_frame_bank_ram #(
  parameter int WORDS = 512,
  parameter int ADDR_WIDTH = (WORDS <= 1) ? 1 : $clog2(WORDS)
) (
  input  logic                  clk,
  input  logic                  wr_en,
  input  logic [ADDR_WIDTH-1:0] wr_addr,
  input  logic [31:0]           wr_data,
  input  logic [ADDR_WIDTH-1:0] rd_addr,
  output logic [31:0]           rd_data
);
  (* ram_style = "block" *) logic [31:0] mem [0:WORDS-1];

  always_ff @(posedge clk) begin
    if (wr_en)
      mem[wr_addr] <= wr_data;
    rd_data <= mem[rd_addr];
  end
endmodule
