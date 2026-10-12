`timescale 1ns/1ps

module phy_reset_timer #(
  // Hardware defaults for a 125 MHz clock.
  parameter integer RESET_LOW_CYCLES       = 125,
  parameter integer POST_RESET_GUARD_CYCLES = 24375,
  parameter integer POWERUP_GUARD_CYCLES    = 25000000
) (
  input  wire clk,
  input  wire reset,
  output reg  phy_reset_n,
  output reg  init_start,
  output reg  ready
);

  localparam integer TOTAL_W =
    (POWERUP_GUARD_CYCLES <= 1) ? 1 : $clog2(POWERUP_GUARD_CYCLES + 1);
  localparam integer POST_W =
    (POST_RESET_GUARD_CYCLES <= 1) ? 1 : $clog2(POST_RESET_GUARD_CYCLES + 1);
  localparam integer LOW_W =
    (RESET_LOW_CYCLES <= 1) ? 1 : $clog2(RESET_LOW_CYCLES + 1);

  reg [TOTAL_W-1:0] total_count;
  reg [POST_W-1:0]  post_count;
  reg [LOW_W-1:0]   low_count;

  initial begin
    if (RESET_LOW_CYCLES < 1)
      $error("RESET_LOW_CYCLES must be at least 1");
    if (POST_RESET_GUARD_CYCLES < 1)
      $error("POST_RESET_GUARD_CYCLES must be at least 1");
    if (POWERUP_GUARD_CYCLES < RESET_LOW_CYCLES)
      $error("POWERUP_GUARD_CYCLES must cover RESET_LOW_CYCLES");
  end

  always @(posedge clk) begin
    if (reset) begin
      phy_reset_n <= 1'b0;
      init_start  <= 1'b0;
      ready       <= 1'b0;
      total_count <= {TOTAL_W{1'b0}};
      post_count  <= {POST_W{1'b0}};
      low_count   <= {LOW_W{1'b0}};
    end else begin
      init_start <= 1'b0;

      if (total_count < POWERUP_GUARD_CYCLES)
        total_count <= total_count + 1'b1;

      if (!phy_reset_n) begin
        if (low_count + 1 >= RESET_LOW_CYCLES) begin
          phy_reset_n <= 1'b1;
          post_count  <= {POST_W{1'b0}};
        end else begin
          low_count <= low_count + 1'b1;
        end
      end else if (post_count < POST_RESET_GUARD_CYCLES) begin
        post_count <= post_count + 1'b1;
      end

      if (!ready && phy_reset_n &&
          total_count >= POWERUP_GUARD_CYCLES &&
          post_count >= POST_RESET_GUARD_CYCLES) begin
        ready      <= 1'b1;
        init_start <= 1'b1;
      end
    end
  end

endmodule
