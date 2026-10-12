module p4fab_tx_frame_store_32to8 #(
  parameter int MAX_FRAME_BYTES = 2048,
  parameter int NUM_BANKS       = 3,
  parameter int COUNTER_WIDTH   = 32
) (
  input  logic clk,
  input  logic aresetn,

  input  logic [31:0] s_axis_tdata,
  input  logic [3:0]  s_axis_tkeep,
  input  logic        s_axis_tvalid,
  output logic        s_axis_tready,
  input  logic        s_axis_tlast,

  output logic [7:0] tx_tdata,
  output logic       tx_tvalid,
  input  logic       tx_tready,
  output logic       tx_tlast,

  output logic [COUNTER_WIDTH-1:0] tx_input_frames,
  output logic [COUNTER_WIDTH-1:0] tx_completed_frames,
  output logic [COUNTER_WIDTH-1:0] tx_protocol_error_frames,
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

  typedef enum logic {TX_IDLE, TX_CAPTURE} capture_state_t;

  logic bank_wr_en [0:NUM_BANKS-1];
  logic [WORD_INDEX_W-1:0] bank_wr_addr [0:NUM_BANKS-1];
  logic [31:0] bank_wr_data [0:NUM_BANKS-1];
  logic [WORD_INDEX_W-1:0] bank_rd_addr [0:NUM_BANKS-1];
  logic [31:0] bank_rd_data [0:NUM_BANKS-1];
  bank_state_t bank_state [0:NUM_BANKS-1];
  logic [WORD_INDEX_W:0] bank_word_count [0:NUM_BANKS-1];
  logic [3:0] bank_final_keep [0:NUM_BANKS-1];
  logic [COUNTER_WIDTH-1:0] bank_byte_count [0:NUM_BANKS-1];

  logic [BANK_INDEX_W-1:0] commit_queue [0:NUM_BANKS-1];
  logic [BANK_INDEX_W-1:0] queue_head, queue_tail;
  logic [BANK_COUNT_W-1:0] queue_count;

  capture_state_t capture_state;
  logic [BANK_INDEX_W-1:0] capture_bank;
  logic [WORD_INDEX_W:0] capture_words;
  logic [COUNTER_WIDTH-1:0] capture_bytes;
  logic capture_error;

  logic reader_active;
  logic reader_load_pending;
  logic [BANK_INDEX_W-1:0] drain_bank;
  logic [WORD_INDEX_W-1:0] drain_word;
  logic [1:0] drain_lane;
  logic [31:0] current_word;

  logic free_found;
  logic [BANK_INDEX_W-1:0] free_bank_index;
  logic input_fire;
  logic keep_legal_final;
  logic beat_legal;
  logic [2:0] input_byte_count;
  logic commit_event, protocol_error_event;
  logic [BANK_INDEX_W-1:0] commit_bank;
  logic [COUNTER_WIDTH-1:0] commit_bytes;
  logic reader_start_event, reader_final_event;
  logic [COUNTER_WIDTH-1:0] rollback_bytes;
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
      4'b1111: keep_byte_count = 3'd4;
      default: keep_byte_count = 3'd0;
    endcase
  endfunction

  always_comb begin
    free_found = 1'b0;
    free_bank_index = '0;
    free_banks = '0;
    bank_states = '0;
    for (int bank = 0; bank < NUM_BANKS; bank++) begin
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

  always_comb begin
    for (int bank = 0; bank < NUM_BANKS; bank++) begin
      bank_wr_en[bank] = 1'b0;
      bank_wr_addr[bank] = '0;
      bank_wr_data[bank] = '0;
      bank_rd_addr[bank] = '0;
      if (reader_start_event && commit_queue[queue_head] == bank[BANK_INDEX_W-1:0])
        bank_rd_addr[bank] = '0;
      else if (reader_active && drain_bank == bank[BANK_INDEX_W-1:0]) begin
        // At the lane-3 handshake the serializer consumes the prefetched
        // word, so request the following word in that same cycle.
        if (tx_tvalid && tx_tready && !tx_tlast && drain_lane == 2'd3)
          bank_rd_addr[bank] = drain_word + 2'd2;
        else
          bank_rd_addr[bank] = drain_word + 1'b1;
      end
    end

    if (input_fire) begin
      if (capture_state == TX_IDLE && beat_legal &&
          input_byte_count <= MAX_FRAME_BYTES) begin
        bank_wr_en[free_bank_index] = 1'b1;
        bank_wr_addr[free_bank_index] = '0;
        bank_wr_data[free_bank_index] = s_axis_tdata;
      end else if (capture_state == TX_CAPTURE && !capture_error && beat_legal &&
                   capture_bytes + input_byte_count <= MAX_FRAME_BYTES) begin
        bank_wr_en[capture_bank] = 1'b1;
        bank_wr_addr[capture_bank] = capture_words[WORD_INDEX_W-1:0];
        bank_wr_data[capture_bank] = s_axis_tdata;
      end
    end
  end

  always_comb begin
    s_axis_tready = (capture_state == TX_CAPTURE) || free_found;
    input_fire = s_axis_tvalid && s_axis_tready;
    input_byte_count = keep_byte_count(s_axis_tkeep);
    keep_legal_final = (s_axis_tkeep == 4'b0001) ||
                       (s_axis_tkeep == 4'b0011) ||
                       (s_axis_tkeep == 4'b0111) ||
                       (s_axis_tkeep == 4'b1111);
    beat_legal = s_axis_tlast ? keep_legal_final : (s_axis_tkeep == 4'b1111);

    commit_event = 1'b0;
    protocol_error_event = 1'b0;
    commit_bank = (capture_state == TX_CAPTURE) ? capture_bank : free_bank_index;
    commit_bytes = (capture_state == TX_CAPTURE) ?
                   capture_bytes + input_byte_count : input_byte_count;
    rollback_bytes = '0;
    if (input_fire) begin
      if (capture_state == TX_IDLE) begin
        if (s_axis_tlast) begin
          if (beat_legal && input_byte_count <= MAX_FRAME_BYTES)
            commit_event = 1'b1;
          else
            protocol_error_event = 1'b1;
        end
      end else begin
        if ((!capture_error && (!beat_legal ||
             (capture_bytes + input_byte_count > MAX_FRAME_BYTES)))) begin
          rollback_bytes = capture_bytes;
        end
        if (s_axis_tlast) begin
          if (!capture_error && beat_legal &&
              (capture_bytes + input_byte_count <= MAX_FRAME_BYTES))
            commit_event = 1'b1;
          else
            protocol_error_event = 1'b1;
        end
      end
    end

    reader_start_event = !reader_active && !tx_tvalid && (queue_count != 0);
    reader_final_event = tx_tvalid && tx_tready && tx_tlast;

    // Level includes bytes in a candidate capture until it is found invalid;
    // that candidate is then rolled back atomically.  Output handshakes remove
    // one real byte at a time.
    level_delta = '0;
    if (input_fire && beat_legal &&
        ((capture_state == TX_IDLE && input_byte_count <= MAX_FRAME_BYTES) ||
         (capture_state == TX_CAPTURE && !capture_error &&
          capture_bytes + input_byte_count <= MAX_FRAME_BYTES)))
      level_delta = level_delta + $signed({1'b0, input_byte_count});
    if (rollback_bytes != 0)
      level_delta = level_delta - $signed({1'b0, rollback_bytes});
    if (tx_tvalid && tx_tready)
      level_delta = level_delta - 1;
    level_after_delta = $signed({1'b0, current_level_bytes}) + level_delta;
  end

  initial begin
    if (MAX_FRAME_BYTES < 1 || (MAX_FRAME_BYTES % 4) != 0)
      $error("MAX_FRAME_BYTES must be a positive multiple of four");
    if (NUM_BANKS < 2)
      $error("NUM_BANKS must be at least 2");
  end

  always_ff @(posedge clk or negedge aresetn) begin
    if (!aresetn) begin
      capture_state <= TX_IDLE;
      capture_bank <= '0;
      capture_words <= '0;
      capture_bytes <= '0;
      capture_error <= 1'b0;
      queue_head <= '0;
      queue_tail <= '0;
      queue_count <= '0;
      reader_active <= 1'b0;
      reader_load_pending <= 1'b0;
      drain_bank <= '0;
      drain_word <= '0;
      drain_lane <= '0;
      current_word <= '0;
      tx_tdata <= '0;
      tx_tvalid <= 1'b0;
      tx_tlast <= 1'b0;
      tx_input_frames <= '0;
      tx_completed_frames <= '0;
      tx_protocol_error_frames <= '0;
      current_level_bytes <= '0;
      max_level_bytes <= '0;
      committed_frames <= '0;
      for (int bank = 0; bank < NUM_BANKS; bank++) begin
        bank_state[bank] <= BANK_FREE;
        bank_word_count[bank] <= '0;
        bank_final_keep[bank] <= '0;
        bank_byte_count[bank] <= '0;
        commit_queue[bank] <= '0;
      end
    end else begin
      current_level_bytes <= level_after_delta[COUNTER_WIDTH-1:0];
      if (level_after_delta > {1'b0, max_level_bytes})
        max_level_bytes <= level_after_delta[COUNTER_WIDTH-1:0];

      if (input_fire) begin
        if (capture_state == TX_IDLE) begin
          bank_state[free_bank_index] <= BANK_CAPTURING;
          capture_bank <= free_bank_index;
          capture_words <= 1;
          capture_bytes <= input_byte_count;
          capture_error <= !beat_legal || (input_byte_count > MAX_FRAME_BYTES);
          if (s_axis_tlast) begin
            capture_state <= TX_IDLE;
            if (commit_event) begin
              bank_state[free_bank_index] <= BANK_COMMITTED;
              bank_word_count[free_bank_index] <= 1;
              bank_final_keep[free_bank_index] <= s_axis_tkeep;
              bank_byte_count[free_bank_index] <= input_byte_count;
              tx_input_frames <= tx_input_frames + 1'b1;
            end else begin
              bank_state[free_bank_index] <= BANK_FREE;
              tx_protocol_error_frames <= tx_protocol_error_frames + 1'b1;
            end
          end else begin
            capture_state <= TX_CAPTURE;
          end
        end else begin
          if (!capture_error && beat_legal &&
              capture_bytes + input_byte_count <= MAX_FRAME_BYTES) begin
            capture_words <= capture_words + 1'b1;
            capture_bytes <= capture_bytes + input_byte_count;
          end else if (!capture_error) begin
            capture_error <= 1'b1;
            capture_bytes <= '0;
          end

          if (s_axis_tlast) begin
            capture_state <= TX_IDLE;
            capture_error <= 1'b0;
            if (commit_event) begin
              bank_state[capture_bank] <= BANK_COMMITTED;
              bank_word_count[capture_bank] <= capture_words + 1'b1;
              bank_final_keep[capture_bank] <= s_axis_tkeep;
              bank_byte_count[capture_bank] <= capture_bytes + input_byte_count;
              tx_input_frames <= tx_input_frames + 1'b1;
            end else begin
              bank_state[capture_bank] <= BANK_FREE;
              tx_protocol_error_frames <= tx_protocol_error_frames + 1'b1;
            end
            capture_words <= '0;
            capture_bytes <= '0;
          end
        end
      end

      if (commit_event) begin
        commit_queue[queue_tail] <= commit_bank;
        queue_tail <= next_bank_index(queue_tail);
      end
      if (reader_start_event) begin
        drain_bank <= commit_queue[queue_head];
        drain_word <= '0;
        drain_lane <= '0;
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

      if (reader_load_pending) begin
        current_word <= bank_rd_data[drain_bank];
        tx_tdata <= bank_rd_data[drain_bank][7:0];
        tx_tlast <= (bank_byte_count[drain_bank] == 1);
        tx_tvalid <= 1'b1;
        reader_load_pending <= 1'b0;
      end

      if (tx_tvalid && tx_tready) begin
        if (tx_tlast) begin
          bank_state[drain_bank] <= BANK_FREE;
          reader_active <= 1'b0;
          tx_tvalid <= 1'b0;
          tx_tlast <= 1'b0;
          tx_completed_frames <= tx_completed_frames + 1'b1;
        end else begin
          case (drain_lane)
            2'd0: begin drain_lane <= 2'd1; tx_tdata <= current_word[15:8]; end
            2'd1: begin
              drain_lane <= 2'd2;
              tx_tdata <= current_word[23:16];
            end
            2'd2: begin drain_lane <= 2'd3; tx_tdata <= current_word[31:24]; end
            default: begin
              drain_lane <= '0;
              drain_word <= drain_word + 1'b1;
              current_word <= bank_rd_data[drain_bank];
              tx_tdata <= bank_rd_data[drain_bank][7:0];
            end
          endcase
          // The next byte is final exactly when its zero-based byte index is
          // frame_length-1.  drain_word/lane describe the byte just accepted.
          tx_tlast <= ((({drain_word, 2'b00} + drain_lane) + 2) ==
                       bank_byte_count[drain_bank]);
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
