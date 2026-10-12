`timescale 1ns/1ps

module dp83867_init #(
  parameter [4:0] PHY_ADDR = 5'd2,
  parameter [15:0] RGMIIDCTL_VALUE = 16'h0077,
  parameter integer SOFT_RESET_WAIT_CYCLES = 2500,
  parameter integer AN_POLL_LIMIT = 10000
) (
  input  wire        clk,
  input  wire        reset,
  input  wire        init_start,

  output reg         init_busy,
  output reg         init_done,
  output reg         init_error,
  output reg  [2:0]  error_code,
  output reg         link_1000_full,

  output reg         mdio_start,
  output reg         mdio_read_not_write,
  output wire [4:0]  mdio_phy_addr,
  output reg  [4:0]  mdio_reg_addr,
  output reg  [15:0] mdio_write_data,
  input  wire [15:0] mdio_read_data,
  input  wire        mdio_busy,
  input  wire        mdio_done,
  input  wire        mdio_error
);

  localparam [2:0] ERR_NONE    = 3'd0;
  localparam [2:0] ERR_MDIO    = 3'd1;
  localparam [2:0] ERR_PHY_ID  = 3'd2;
  localparam [2:0] ERR_READBACK= 3'd3;
  localparam [2:0] ERR_AN_TO   = 3'd4;
  localparam [2:0] ERR_MODE    = 3'd5;

  localparam [1:0] OP_C22_READ  = 2'd0;
  localparam [1:0] OP_C22_WRITE = 2'd1;
  localparam [1:0] OP_MMD_READ  = 2'd2;
  localparam [1:0] OP_MMD_WRITE = 2'd3;

  localparam [1:0] O_IDLE  = 2'd0;
  localparam [1:0] O_ISSUE = 2'd1;
  localparam [1:0] O_WAIT  = 2'd2;

  // Clause-22 registers and DP83867 extended-register addresses.
  localparam [4:0] REG_BMCR       = 5'h00;
  localparam [4:0] REG_BMSR       = 5'h01;
  localparam [4:0] REG_PHYID1     = 5'h02;
  localparam [4:0] REG_PHYID2     = 5'h03;
  localparam [4:0] REG_ADVERTISE  = 5'h04;
  localparam [4:0] REG_CTRL1000   = 5'h09;
  localparam [4:0] REG_PHYCTRL    = 5'h10;
  localparam [4:0] REG_PHYSTS     = 5'h11;
  localparam [4:0] REG_CFG2       = 5'h14;
  localparam [4:0] REG_CFG3       = 5'h1e;
  localparam [4:0] REG_CTRL       = 5'h1f;
  localparam [4:0] REG_REGCR      = 5'h0d;
  localparam [4:0] REG_ADDAR      = 5'h0e;

  localparam [4:0]  MMD_DEVADDR   = 5'h1f;
  localparam [15:0] MMD_FLD_THR_CFG = 16'h002e;
  localparam [15:0] MMD_CFG4        = 16'h0031;
  localparam [15:0] MMD_RGMIICTL    = 16'h0032;
  localparam [15:0] MMD_STRAP_STS1  = 16'h006e;
  localparam [15:0] MMD_STRAP_STS2  = 16'h006f;
  localparam [15:0] MMD_RGMIIDCTL   = 16'h0086;
  localparam [15:0] MMD_DSP_FFE_CFG = 16'h012c;

  assign mdio_phy_addr = PHY_ADDR;

  reg [1:0]  op_state;
  reg [1:0]  op_kind;
  reg [1:0]  op_phase;
  reg [4:0]  op_c22_reg;
  reg [4:0]  op_devad;
  reg [15:0] op_ext_reg;
  reg [15:0] op_write_value;
  reg [15:0] op_read_value;
  reg        op_start;
  reg        op_done;
  reg        op_error;

  reg [6:0]  seq_step;
  reg        seq_waiting;
  reg [15:0] saved_value;
  reg        strap1_fix;
  reg [31:0] wait_count;
  reg [31:0] an_poll_count;

  initial begin
    if (SOFT_RESET_WAIT_CYCLES < 1)
      $error("SOFT_RESET_WAIT_CYCLES must be at least 1");
    if (AN_POLL_LIMIT < 1)
      $error("AN_POLL_LIMIT must be at least 1");
  end

  // One logical operation is either one Clause-22 access or the standard
  // four-access Clause-22 indirect sequence for one MMD access.
  always @(posedge clk) begin
    if (reset) begin
      op_state           <= O_IDLE;
      op_phase           <= 2'd0;
      op_read_value      <= 16'd0;
      op_done            <= 1'b0;
      op_error           <= 1'b0;
      mdio_start         <= 1'b0;
      mdio_read_not_write<= 1'b0;
      mdio_reg_addr      <= 5'd0;
      mdio_write_data    <= 16'd0;
    end else begin
      op_done    <= 1'b0;
      op_error   <= 1'b0;
      mdio_start <= 1'b0;

      case (op_state)
        O_IDLE: begin
          if (op_start) begin
            op_phase <= 2'd0;
            op_state <= O_ISSUE;
          end
        end

        O_ISSUE: begin
          if (!mdio_busy) begin
            if (op_kind == OP_C22_READ || op_kind == OP_C22_WRITE) begin
              mdio_read_not_write <= (op_kind == OP_C22_READ);
              mdio_reg_addr       <= op_c22_reg;
              mdio_write_data     <= op_write_value;
            end else begin
              case (op_phase)
                2'd0: begin
                  mdio_read_not_write <= 1'b0;
                  mdio_reg_addr       <= REG_REGCR;
                  mdio_write_data     <= {11'd0, op_devad};
                end
                2'd1: begin
                  mdio_read_not_write <= 1'b0;
                  mdio_reg_addr       <= REG_ADDAR;
                  mdio_write_data     <= op_ext_reg;
                end
                2'd2: begin
                  mdio_read_not_write <= 1'b0;
                  mdio_reg_addr       <= REG_REGCR;
                  mdio_write_data     <= {2'b01, 9'd0, op_devad};
                end
                default: begin
                  mdio_read_not_write <= (op_kind == OP_MMD_READ);
                  mdio_reg_addr       <= REG_ADDAR;
                  mdio_write_data     <= op_write_value;
                end
              endcase
            end
            mdio_start <= 1'b1;
            op_state   <= O_WAIT;
          end
        end

        O_WAIT: begin
          if (mdio_done) begin
            if (mdio_error) begin
              op_error <= 1'b1;
              op_done  <= 1'b1;
              op_state <= O_IDLE;
            end else if ((op_kind == OP_C22_READ) ||
                         (op_kind == OP_C22_WRITE) ||
                         (op_phase == 2'd3)) begin
              if (op_kind == OP_C22_READ || op_kind == OP_MMD_READ)
                op_read_value <= mdio_read_data;
              op_done  <= 1'b1;
              op_state <= O_IDLE;
            end else begin
              op_phase <= op_phase + 1'b1;
              op_state <= O_ISSUE;
            end
          end
        end

        default: op_state <= O_IDLE;
      endcase
    end
  end

  // Fixed Linux-baseline initialization sequence.  Each numbered step either
  // launches one logical operation or implements a bounded delay/poll branch.
  always @(posedge clk) begin
    if (reset) begin
      init_busy       <= 1'b0;
      init_done       <= 1'b0;
      init_error      <= 1'b0;
      error_code      <= ERR_NONE;
      link_1000_full  <= 1'b0;
      op_start        <= 1'b0;
      seq_step        <= 7'd0;
      seq_waiting     <= 1'b0;
      saved_value     <= 16'd0;
      strap1_fix      <= 1'b0;
      wait_count      <= 32'd0;
      an_poll_count   <= 32'd0;
      op_kind         <= OP_C22_READ;
      op_c22_reg      <= 5'd0;
      op_devad        <= MMD_DEVADDR;
      op_ext_reg      <= 16'd0;
      op_write_value  <= 16'd0;
    end else begin
      init_done <= 1'b0;
      op_start  <= 1'b0;

      if (!init_busy) begin
        if (init_start) begin
          init_busy      <= 1'b1;
          init_error     <= 1'b0;
          error_code     <= ERR_NONE;
          link_1000_full <= 1'b0;
          seq_step       <= 7'd0;
          seq_waiting    <= 1'b0;
          wait_count     <= 32'd0;
          an_poll_count  <= 32'd0;
        end
      end else if (seq_waiting) begin
        if (op_done) begin
          seq_waiting <= 1'b0;
          if (op_error) begin
            init_busy  <= 1'b0;
            init_error <= 1'b1;
            error_code <= ERR_MDIO;
          end else begin
            case (seq_step)
              7'd0: begin
                if (op_read_value != 16'h2000) begin
                  init_busy  <= 1'b0;
                  init_error <= 1'b1;
                  error_code <= ERR_PHY_ID;
                end else seq_step <= 7'd1;
              end
              7'd1: begin
                if (op_read_value != 16'ha231) begin
                  init_busy  <= 1'b0;
                  init_error <= 1'b1;
                  error_code <= ERR_PHY_ID;
                end else seq_step <= 7'd2;
              end
              7'd4, 7'd9, 7'd11, 7'd14, 7'd16, 7'd18,
              7'd21, 7'd24, 7'd26, 7'd28, 7'd30:
                begin saved_value <= op_read_value; seq_step <= seq_step + 1'b1; end
              7'd13: begin
                if (op_read_value[10]) seq_step <= 7'd14;
                else                   seq_step <= 7'd16;
              end
              7'd19: begin
                strap1_fix <= op_read_value[11];
                seq_step   <= 7'd20;
              end
              7'd32: begin
                if (op_read_value[1:0] != 2'b11) begin
                  init_busy  <= 1'b0;
                  init_error <= 1'b1;
                  error_code <= ERR_READBACK;
                end else seq_step <= 7'd33;
              end
              7'd33: begin
                if (op_read_value != RGMIIDCTL_VALUE) begin
                  init_busy  <= 1'b0;
                  init_error <= 1'b1;
                  error_code <= ERR_READBACK;
                end else seq_step <= 7'd34;
              end
              7'd34: seq_step <= 7'd35; // first BMSR read clears latched-low
              7'd35: begin
                if (op_read_value[5] && op_read_value[2]) begin
                  seq_step <= 7'd36;
                end else if (an_poll_count + 1 >= AN_POLL_LIMIT) begin
                  init_busy  <= 1'b0;
                  init_error <= 1'b1;
                  error_code <= ERR_AN_TO;
                end else begin
                  an_poll_count <= an_poll_count + 1'b1;
                  seq_step      <= 7'd34;
                end
              end
              7'd36: begin
                if (op_read_value[10] && op_read_value[15] && op_read_value[13]) begin
                  init_busy      <= 1'b0;
                  init_done      <= 1'b1;
                  link_1000_full <= 1'b1;
                end else begin
                  init_busy  <= 1'b0;
                  init_error <= 1'b1;
                  error_code <= ERR_MODE;
                end
              end
              default: seq_step <= seq_step + 1'b1;
            endcase
          end
        end
      end else begin
        case (seq_step)
          7'd0:  launch_c22_read(REG_PHYID1);
          7'd1:  launch_c22_read(REG_PHYID2);
          7'd2:  launch_c22_write(REG_CTRL, 16'h8000);
          7'd3: begin
            if (wait_count + 1 >= SOFT_RESET_WAIT_CYCLES) begin
              wait_count <= 32'd0; seq_step <= 7'd4;
            end else wait_count <= wait_count + 1'b1;
          end
          7'd4:  launch_c22_read(REG_PHYCTRL);
          7'd5:  launch_c22_write(REG_PHYCTRL, saved_value & 16'hfbff);
          7'd6:  launch_mmd_write(MMD_DSP_FFE_CFG, 16'h0e81);
          7'd7:  launch_c22_write(REG_CTRL, 16'h4000);
          7'd8: begin
            if (wait_count + 1 >= SOFT_RESET_WAIT_CYCLES) begin
              wait_count <= 32'd0; seq_step <= 7'd9;
            end else wait_count <= wait_count + 1'b1;
          end
          7'd9:  launch_c22_read(REG_CFG2);
          7'd10: launch_c22_write(REG_CFG2, (saved_value & 16'hfcff) | 16'h0300);
          7'd11: launch_mmd_read(MMD_CFG4);
          7'd12: launch_mmd_write(MMD_CFG4, saved_value & 16'hff7f);
          7'd13: launch_mmd_read(MMD_STRAP_STS2);
          7'd14: launch_mmd_read(MMD_FLD_THR_CFG);
          7'd15: launch_mmd_write(MMD_FLD_THR_CFG, (saved_value & 16'hfff8) | 16'h0001);
          7'd16: launch_c22_read(REG_PHYCTRL);
          7'd17: launch_c22_write(REG_PHYCTRL, (saved_value & 16'h3bff) | 16'h4000);
          7'd18: launch_c22_read(REG_PHYCTRL);
          7'd19: launch_mmd_read(MMD_STRAP_STS1);
          7'd20: launch_c22_write(REG_PHYCTRL,
                    strap1_fix ? (saved_value & 16'hf7ff) : saved_value);
          7'd21: launch_mmd_read(MMD_RGMIICTL);
          7'd22: launch_mmd_write(MMD_RGMIICTL, (saved_value & 16'hfffc) | 16'h0003);
          7'd23: launch_mmd_write(MMD_RGMIIDCTL, RGMIIDCTL_VALUE);
          7'd24: launch_c22_read(REG_CFG3);
          7'd25: launch_c22_write(REG_CFG3, saved_value | 16'h0200);
          7'd26: launch_c22_read(REG_ADVERTISE);
          // Linux genphy mask: 10/100, 100BASE4 and pause/asym-pause.
          // Preserve selector/reserved/next-page fields and advertise the
          // supported copper modes plus symmetric/asymmetric pause.
          7'd27: launch_c22_write(REG_ADVERTISE, (saved_value & 16'hf01f) | 16'h0de0);
          7'd28: launch_c22_read(REG_CTRL1000);
          7'd29: launch_c22_write(REG_CTRL1000, (saved_value & 16'hfcff) | 16'h0300);
          7'd30: launch_c22_read(REG_BMCR);
          7'd31: launch_c22_write(REG_BMCR, (saved_value & 16'hfbff) | 16'h1200);
          7'd32: launch_mmd_read(MMD_RGMIICTL);
          7'd33: launch_mmd_read(MMD_RGMIIDCTL);
          7'd34: launch_c22_read(REG_BMSR);
          7'd35: launch_c22_read(REG_BMSR);
          7'd36: launch_c22_read(REG_PHYSTS);
          default: begin
            init_busy  <= 1'b0;
            init_error <= 1'b1;
            error_code <= ERR_READBACK;
          end
        endcase
      end
    end
  end

  task automatic launch_c22_read(input [4:0] regnum);
    begin
      op_kind       <= OP_C22_READ;
      op_c22_reg    <= regnum;
      op_start      <= 1'b1;
      seq_waiting   <= 1'b1;
    end
  endtask

  task automatic launch_c22_write(input [4:0] regnum, input [15:0] value);
    begin
      op_kind       <= OP_C22_WRITE;
      op_c22_reg    <= regnum;
      op_write_value<= value;
      op_start      <= 1'b1;
      seq_waiting   <= 1'b1;
    end
  endtask

  task automatic launch_mmd_read(input [15:0] regnum);
    begin
      op_kind       <= OP_MMD_READ;
      op_devad      <= MMD_DEVADDR;
      op_ext_reg    <= regnum;
      op_start      <= 1'b1;
      seq_waiting   <= 1'b1;
    end
  endtask

  task automatic launch_mmd_write(input [15:0] regnum, input [15:0] value);
    begin
      op_kind       <= OP_MMD_WRITE;
      op_devad      <= MMD_DEVADDR;
      op_ext_reg    <= regnum;
      op_write_value<= value;
      op_start      <= 1'b1;
      seq_waiting   <= 1'b1;
    end
  endtask

endmodule
