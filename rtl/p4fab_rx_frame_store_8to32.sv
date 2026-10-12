module p4fab_rx_frame_store_8to32 #(
  parameter int MAX_FRAME_BYTES = 2048,
  parameter int NUM_BANKS       = 3,
  parameter int COUNTER_WIDTH   = 32
) (
  input  logic clk,
  input  logic aresetn,

  // Non-backpressurable TEMAC RX client stream.  rx_tuser is meaningful on
  // the final valid byte, matching the existing TEMAC endpoint contract.
  input  logic [7:0] rx_tdata,
  input  logic       rx_tvalid,
  input  logic       rx_tlast,
  input  logic       rx_tuser,
  input  logic [63:0] rx_ingress_timestamp,

  output logic [31:0] m_axis_tdata,
  output logic [3:0]  m_axis_tkeep,
  output logic        m_axis_tvalid,
  input  logic        m_axis_tready,
  output logic        m_axis_tlast,
  output logic [15:0] m_axis_packet_length,
  output logic [63:0] m_axis_ingress_timestamp,

  output logic [COUNTER_WIDTH-1:0] rx_frames,
  output logic [COUNTER_WIDTH-1:0] rx_bytes,
  output logic [COUNTER_WIDTH-1:0] rx_accepted_frames,
  output logic [COUNTER_WIDTH-1:0] rx_busy_drop_frames,
  output logic [COUNTER_WIDTH-1:0] rx_overflow_drop_frames,
  output logic [COUNTER_WIDTH-1:0] rx_bad_frames,
  output logic [COUNTER_WIDTH-1:0] current_level_bytes,
  output logic [COUNTER_WIDTH-1:0] max_level_bytes,
  output logic [$clog2(NUM_BANKS+1)-1:0] committed_frames,
  output logic [$clog2(NUM_BANKS+1)-1:0] free_banks,
  output logic [NUM_BANKS*2-1:0] bank_states
);
  localparam int WORDS_PER_BANK = (MAX_FRAME_BYTES + 3) / 4;
  localparam int WORD_INDEX_W = (WORDS_PER_BANK <= 1) ? 1 : $clog2(WORDS_PER_BANK);
  localparam int BANK_INDEX_W = (NUM_BANKS <= 1) ? 1 : $clog2(NUM_BANKS);
  localparam int BANK_COUNT_W = $clog2(NUM_BANKS + 1);

  typedef enum logic [1:0] {
    BANK_FREE      = 2'b00,
    BANK_CAPTURING = 2'b01,
    BANK_COMMITTED = 2'b10,
    BANK_DRAINING  = 2'b11
  } bank_state_t;

  typedef enum logic [1:0] {
    RX_IDLE,
    RX_CAPTURE,
    RX_DROP_BUSY,
    RX_DROP_OVERFLOW
  } rx_state_t;

  // Each generated instance contains an independent one-dimensional SDP RAM.
  // Bank selection is deliberately outside the memories so Vivado does not
  // interpret bank x word as a dynamically indexed 3-D RAM/register array.
  logic bank_wr_en [0:NUM_BANKS-1];
  logic [WORD_INDEX_W-1:0] bank_wr_addr [0:NUM_BANKS-1];
  logic [31:0] bank_wr_data [0:NUM_BANKS-1];
  logic [WORD_INDEX_W-1:0] bank_rd_addr [0:NUM_BANKS-1];
  logic [31:0] bank_rd_data [0:NUM_BANKS-1];
  bank_state_t bank_state [0:NUM_BANKS-1];
  logic [WORD_INDEX_W:0] bank_word_count [0:NUM_BANKS-1];
  logic [3:0] bank_final_keep [0:NUM_BANKS-1];
  logic [63:0] bank_ingress_timestamp [0:NUM_BANKS-1];

  logic [BANK_INDEX_W-1:0] commit_queue [0:NUM_BANKS-1];
  logic [BANK_INDEX_W-1:0] queue_head, queue_tail;
  logic [BANK_COUNT_W-1:0] queue_count;

  rx_state_t rx_state;
  logic [BANK_INDEX_W-1:0] capture_bank;
  logic [WORD_INDEX_W-1:0] capture_word;
  logic [1:0] capture_lane;
  logic [31:0] assembly_data;
  logic [COUNTER_WIDTH-1:0] capture_bytes;

  logic reader_active;
  logic reader_load_pending;
  logic [BANK_INDEX_W-1:0] drain_bank;
  logic [WORD_INDEX_W-1:0] drain_word;

  logic free_found;
  logic [BANK_INDEX_W-1:0] free_bank_index;
  logic commit_event;
  logic [BANK_INDEX_W-1:0] commit_bank;
  logic reader_start_event;
  logic reader_final_event;
  logic [2:0] output_byte_count;
  logic signed [COUNTER_WIDTH:0] level_delta;
  logic [COUNTER_WIDTH:0] level_after_delta;

  for (genvar ram_bank = 0; ram_bank < NUM_BANKS; ram_bank++) begin : g_bank_ram
    p4fab_frame_bank_ram #(
      .WORDS(WORDS_PER_BANK), .ADDR_WIDTH(WORD_INDEX_W)
    ) u_bank_ram (
      .clk, .wr_en(bank_wr_en[ram_bank]),
      .wr_addr(bank_wr_addr[ram_bank]), .wr_data(bank_wr_data[ram_bank]),
      .rd_addr(bank_rd_addr[ram_bank]), .rd_data(bank_rd_data[ram_bank])
    );
  end

  function automatic [BANK_INDEX_W-1:0] next_bank_index(
    input [BANK_INDEX_W-1:0] index
  );
    if (index == NUM_BANKS-1)
      next_bank_index = '0;
    else
      next_bank_index = index + 1'b1;
  endfunction

  function automatic [2:0] keep_byte_count(input logic [3:0] keep);
    case (keep)
      4'b0001: keep_byte_count = 3'd1;
      4'b0011: keep_byte_count = 3'd2;
      4'b0111: keep_byte_count = 3'd3;
      default: keep_byte_count = 3'd4;
    endcase
  endfunction

  always @* begin
    free_found = 1'b0;
    free_bank_index = '0;
    free_banks = '0;
    bank_states = '0;
    for (int bank = 0; bank < NUM_BANKS; bank = bank + 1) begin
      bank_states[2*bank +: 2] = bank_state[bank];
      if (bank_state[bank] == BANK_FREE) begin
        free_banks = free_banks + 1'b1;
        if (!free_found) begin
          free_found = 1'b1;
          free_bank_index = bank[BANK_INDEX_W-1:0];
        end
      end
    end
  end

  // A committed/draining bank already contains all information required to
  // recover its byte length.  Keep the value constant for every output beat;
  // no additional packet-length counter is needed.
  always @* begin
    m_axis_packet_length = '0;
    m_axis_ingress_timestamp = '0;
    if (reader_active)
      m_axis_packet_length =
        ((bank_word_count[drain_bank] - 1'b1) * 4) +
        keep_byte_count(bank_final_keep[drain_bank]);
    if (reader_active)
      m_axis_ingress_timestamp = bank_ingress_timestamp[drain_bank];
  end

  always @* begin
    for (int bank = 0; bank < NUM_BANKS; bank++) begin
      bank_wr_en[bank] = 1'b0;
      bank_wr_addr[bank] = '0;
      bank_wr_data[bank] = '0;
      bank_rd_addr[bank] = '0;
      if (reader_start_event && commit_queue[queue_head] == bank[BANK_INDEX_W-1:0])
        bank_rd_addr[bank] = '0;
      else if (reader_active && drain_bank == bank[BANK_INDEX_W-1:0]) begin
        // bank_rd_data already holds drain_word+1.  When the current AXIS
        // word handshakes, request drain_word+2 in the same cycle so the
        // registered RAM output remains one word ahead at full throughput.
        if (m_axis_tvalid && m_axis_tready && !m_axis_tlast)
          bank_rd_addr[bank] = drain_word + 2'd2;
        else
          bank_rd_addr[bank] = drain_word + 1'b1;
      end
    end

    if (rx_tvalid) begin
      if (rx_state == RX_IDLE && free_found && rx_tlast) begin
        bank_wr_en[free_bank_index] = 1'b1;
        bank_wr_addr[free_bank_index] = '0;
        bank_wr_data[free_bank_index] = {24'b0, rx_tdata};
      end else if (rx_state == RX_CAPTURE && capture_bytes < MAX_FRAME_BYTES &&
                   (capture_lane == 2'd3 || rx_tlast)) begin
        bank_wr_en[capture_bank] = 1'b1;
        bank_wr_addr[capture_bank] = capture_word;
        case (capture_lane)
          2'd0: bank_wr_data[capture_bank] = {24'b0, rx_tdata};
          2'd1: bank_wr_data[capture_bank] = {16'b0, rx_tdata, assembly_data[7:0]};
          2'd2: bank_wr_data[capture_bank] = {8'b0, rx_tdata, assembly_data[15:0]};
          default: bank_wr_data[capture_bank] = {rx_tdata, assembly_data[23:0]};
        endcase
      end
    end
  end

  always_comb begin
    commit_event = 1'b0;
    commit_bank = capture_bank;
    if (rx_tvalid && rx_tlast && !rx_tuser) begin
      if (rx_state == RX_IDLE && free_found) begin
        commit_event = 1'b1;
        commit_bank = free_bank_index;
      end else if (rx_state == RX_CAPTURE && capture_bytes < MAX_FRAME_BYTES) begin
        commit_event = 1'b1;
        commit_bank = capture_bank;
      end
    end

    reader_start_event = !reader_active && !m_axis_tvalid && (queue_count != 0);
    reader_final_event = m_axis_tvalid && m_axis_tready && m_axis_tlast;
    output_byte_count = keep_byte_count(m_axis_tkeep);

    // current_level_bytes is the number of actual frame bytes held in all
    // CAPTURING, COMMITTED, and DRAINING banks that have not yet handshaken
    // on m_axis.  Dropped-frame rollback removes all bytes of that frame.
    level_delta = '0;
    if (rx_tvalid) begin
      if (rx_state == RX_IDLE && free_found) begin
        if (!rx_tlast || !rx_tuser)
          level_delta = level_delta + 1;
      end else if (rx_state == RX_CAPTURE) begin
        if (capture_bytes >= MAX_FRAME_BYTES)
          level_delta = level_delta - $signed({1'b0, capture_bytes});
        else if (rx_tlast && rx_tuser)
          level_delta = level_delta - $signed({1'b0, capture_bytes});
        else
          level_delta = level_delta + 1;
      end
    end
    if (m_axis_tvalid && m_axis_tready)
      level_delta = level_delta - $signed({{(COUNTER_WIDTH-2){1'b0}}, output_byte_count});

    level_after_delta = $signed({1'b0, current_level_bytes}) + level_delta;
  end

  initial begin
    if (MAX_FRAME_BYTES < 1)
      $error("MAX_FRAME_BYTES must be positive");
    if (NUM_BANKS < 2)
      $error("NUM_BANKS must be at least 2");
  end

  always_ff @(posedge clk or negedge aresetn) begin
    if (!aresetn) begin
      rx_state <= RX_IDLE;
      capture_bank <= '0;
      capture_word <= '0;
      capture_lane <= '0;
      assembly_data <= '0;
      capture_bytes <= '0;
      queue_head <= '0;
      queue_tail <= '0;
      queue_count <= '0;
      reader_active <= 1'b0;
      reader_load_pending <= 1'b0;
      drain_bank <= '0;
      drain_word <= '0;
      m_axis_tdata <= '0;
      m_axis_tkeep <= '0;
      m_axis_tvalid <= 1'b0;
      m_axis_tlast <= 1'b0;
      rx_frames <= '0;
      rx_bytes <= '0;
      rx_accepted_frames <= '0;
      rx_busy_drop_frames <= '0;
      rx_overflow_drop_frames <= '0;
      rx_bad_frames <= '0;
      current_level_bytes <= '0;
      max_level_bytes <= '0;
      committed_frames <= '0;
      for (int bank = 0; bank < NUM_BANKS; bank = bank + 1) begin
        bank_state[bank] <= BANK_FREE;
        bank_word_count[bank] <= '0;
        bank_final_keep[bank] <= '0;
        bank_ingress_timestamp[bank] <= '0;
        commit_queue[bank] <= '0;
      end
    end else begin
      current_level_bytes <= level_after_delta[COUNTER_WIDTH-1:0];
      if (level_after_delta > {1'b0, max_level_bytes})
        max_level_bytes <= level_after_delta[COUNTER_WIDTH-1:0];

      if (rx_tvalid)
        rx_bytes <= rx_bytes + 1'b1;
      if (rx_tvalid && rx_tlast)
        rx_frames <= rx_frames + 1'b1;

      case (rx_state)
        RX_IDLE: begin
          if (rx_tvalid) begin
            if (!free_found) begin
              rx_busy_drop_frames <= rx_busy_drop_frames + 1'b1;
              if (!rx_tlast)
                rx_state <= RX_DROP_BUSY;
            end else if (rx_tlast) begin
              bank_ingress_timestamp[free_bank_index] <= rx_ingress_timestamp;
              bank_word_count[free_bank_index] <= 1;
              bank_final_keep[free_bank_index] <= 4'b0001;
              if (rx_tuser) begin
                rx_bad_frames <= rx_bad_frames + 1'b1;
                bank_state[free_bank_index] <= BANK_FREE;
              end else begin
                bank_state[free_bank_index] <= BANK_COMMITTED;
                rx_accepted_frames <= rx_accepted_frames + 1'b1;
              end
            end else begin
              bank_ingress_timestamp[free_bank_index] <= rx_ingress_timestamp;
              capture_bank <= free_bank_index;
              capture_word <= '0;
              capture_lane <= 2'd1;
              assembly_data <= {24'b0, rx_tdata};
              capture_bytes <= 1;
              bank_state[free_bank_index] <= BANK_CAPTURING;
              rx_state <= RX_CAPTURE;
            end
          end
        end

        RX_CAPTURE: begin
          if (rx_tvalid) begin
            if (capture_bytes >= MAX_FRAME_BYTES) begin
              bank_state[capture_bank] <= BANK_FREE;
              capture_bytes <= '0;
              capture_lane <= '0;
              capture_word <= '0;
              assembly_data <= '0;
              rx_overflow_drop_frames <= rx_overflow_drop_frames + 1'b1;
              if (rx_tlast)
                rx_state <= RX_IDLE;
              else
                rx_state <= RX_DROP_OVERFLOW;
            end else begin
              case (capture_lane)
                2'd0: assembly_data <= {24'b0, rx_tdata};
                2'd1: assembly_data[15:8] <= rx_tdata;
                2'd2: assembly_data[23:16] <= rx_tdata;
                default: begin
                  assembly_data <= '0;
                end
              endcase
              capture_bytes <= capture_bytes + 1'b1;

              if (rx_tlast) begin
                bank_word_count[capture_bank] <= capture_word + 1'b1;
                case (capture_lane)
                  2'd0: bank_final_keep[capture_bank] <= 4'b0001;
                  2'd1: bank_final_keep[capture_bank] <= 4'b0011;
                  2'd2: bank_final_keep[capture_bank] <= 4'b0111;
                  default: bank_final_keep[capture_bank] <= 4'b1111;
                endcase
                if (rx_tuser) begin
                  bank_state[capture_bank] <= BANK_FREE;
                  rx_bad_frames <= rx_bad_frames + 1'b1;
                end else begin
                  bank_state[capture_bank] <= BANK_COMMITTED;
                  rx_accepted_frames <= rx_accepted_frames + 1'b1;
                end
                capture_bytes <= '0;
                capture_lane <= '0;
                capture_word <= '0;
                assembly_data <= '0;
                rx_state <= RX_IDLE;
              end else if (capture_lane == 2'd3) begin
                capture_lane <= '0;
                capture_word <= capture_word + 1'b1;
              end else begin
                capture_lane <= capture_lane + 1'b1;
              end
            end
          end
        end

        RX_DROP_BUSY: begin
          if (rx_tvalid && rx_tlast)
            rx_state <= RX_IDLE;
        end

        RX_DROP_OVERFLOW: begin
          if (rx_tvalid && rx_tlast)
            rx_state <= RX_IDLE;
        end
      endcase

      // A normal TLAST publishes exactly one completed bank to the ordering
      // queue.  A reader pop may occur in the same cycle.
      if (commit_event) begin
        commit_queue[queue_tail] <= commit_bank;
        queue_tail <= next_bank_index(queue_tail);
      end
      if (reader_start_event) begin
        drain_bank <= commit_queue[queue_head];
        drain_word <= '0;
        reader_active <= 1'b1;
        reader_load_pending <= 1'b1;
        bank_state[commit_queue[queue_head]] <= BANK_DRAINING;
        queue_head <= next_bank_index(queue_head);
      end
      case ({commit_event, reader_start_event})
        2'b10: queue_count <= queue_count + 1'b1;
        2'b01: queue_count <= queue_count - 1'b1;
        default: queue_count <= queue_count;
      endcase

      // The bank RAM has a one-cycle synchronous read.  The request issued
      // by reader_start_event is published only after its registered output
      // is available; no partial frame is exposed during that latency.
      if (reader_load_pending) begin
        m_axis_tdata <= bank_rd_data[drain_bank];
        m_axis_tkeep <= (bank_word_count[drain_bank] == 1) ?
                        bank_final_keep[drain_bank] : 4'b1111;
        m_axis_tlast <= (bank_word_count[drain_bank] == 1);
        m_axis_tvalid <= 1'b1;
        reader_load_pending <= 1'b0;
      end

      if (m_axis_tvalid && m_axis_tready) begin
        if (m_axis_tlast) begin
          bank_state[drain_bank] <= BANK_FREE;
          reader_active <= 1'b0;
          m_axis_tvalid <= 1'b0;
          m_axis_tkeep <= '0;
          m_axis_tlast <= 1'b0;
        end else begin
          drain_word <= drain_word + 1'b1;
          m_axis_tdata <= bank_rd_data[drain_bank];
          if ((drain_word + 2) == bank_word_count[drain_bank]) begin
            m_axis_tkeep <= bank_final_keep[drain_bank];
            m_axis_tlast <= 1'b1;
          end else begin
            m_axis_tkeep <= 4'b1111;
            m_axis_tlast <= 1'b0;
          end
        end
      end

      case ({commit_event, reader_final_event})
        2'b10: committed_frames <= committed_frames + 1'b1;
        2'b01: committed_frames <= committed_frames - 1'b1;
        default: committed_frames <= committed_frames;
      endcase
    end
  end
endmodule
