// rtl/user_domain/tiny_cache.sv
// Tiny direct-mapped cache as an OBI subordinate on the user_sbr bus.

module tiny_cache
  import croc_pkg::*;
  import user_pkg::*;
  #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = SbrObiCfg.DataWidth,
    parameter int unsigned LINE_BYTES = 16,   // 16-byte lines
    parameter int unsigned NUM_LINES  = 64    // 64-line direct mapped
  ) (
    input  logic       clk_i,
    input  logic       rst_ni,

    // OBI subordinate interface (user_sbr slice from obi_demux)
    input  sbr_obi_req_t obi_req_i,
    output sbr_obi_rsp_t obi_rsp_o
  );

 function automatic int clog2_int (input int value);
    int tmp;
    begin
      if (value <= 1) begin
        clog2_int = 0;
      end else begin
        tmp = value - 1;
        clog2_int = 0;
        while (tmp > 0) begin
          clog2_int = clog2_int + 1;
          tmp = tmp >> 1;
        end
      end
    end
  endfunction

  // Address breakdown
  localparam int unsigned OFFSET_BITS = clog2_int(LINE_BYTES);
  localparam int unsigned INDEX_BITS  = clog2_int(NUM_LINES);
  localparam int unsigned TAG_WIDTH   = ADDR_WIDTH - OFFSET_BITS - INDEX_BITS;

  // Combinational index/tag from current address
  logic [INDEX_BITS-1:0] index_c;
  logic [TAG_WIDTH-1:0]  tag_c;

  assign index_c = obi_req_i.a.addr[OFFSET_BITS + INDEX_BITS - 1 : OFFSET_BITS];
  assign tag_c   = obi_req_i.a.addr[ADDR_WIDTH-1 : OFFSET_BITS + INDEX_BITS];

  // Latched index/tag from accepted request
  logic [INDEX_BITS-1:0] index_q;
  logic [TAG_WIDTH-1:0]  tag_q;

  // Tag / valid / data arrays
  logic [TAG_WIDTH-1:0]  tag_array   [NUM_LINES-1:0];
  logic                  valid_array [NUM_LINES-1:0];
  logic [DATA_WIDTH-1:0] data_array  [NUM_LINES-1:0];

  // FSM
  typedef enum logic [1:0] {
    IDLE,
    LOOKUP,
    MISS_REQ,
    MISS_WAIT
  } cache_state_e;

  cache_state_e state_q, state_d;

  // Latched request info
  logic                 we_q;
  logic [DATA_WIDTH-1:0] wdata_q;

  // Hit/miss and data using latched index/tag
  logic hit;
  logic [DATA_WIDTH-1:0] line_data;

  assign line_data = data_array[index_q];
  assign hit       = valid_array[index_q] && (tag_array[index_q] == tag_q);

  // Response register
  sbr_obi_rsp_t rsp_q, rsp_d;

  // Combinational FSM + response
  always_comb begin
    rsp_d     = '0;
    rsp_d.err = 1'b0;
    state_d   = state_q;

    unique case (state_q)
      IDLE: begin
        // Wait for a request; when we see one, accept it and go LOOKUP.
        if (obi_req_i.req) begin
          rsp_d.gnt = 1'b1;   // grant in same cycle as accept
          state_d   = LOOKUP;
        end
      end

      LOOKUP: begin
        // We already latched addr/we/wdata in the seq block.
        if (hit) begin
          if (!we_q) begin
            // READ hit
            rsp_d.rdata  = line_data;
            rsp_d.rvalid = 1'b1;
          end
          // WRITE hit: data_array updated in seq block
          state_d = IDLE;
        end else begin
          // MISS: in a full design we'd talk to an external memory.
          // Here we just model a multi-cycle miss and "refill" with zeros.
          state_d = MISS_REQ;
        end
      end

      MISS_REQ: begin
        // Could assert a mem_req_o here in a full design.
        // For now this is just a 1-cycle pre-refill state.
        state_d = MISS_WAIT;
      end

      MISS_WAIT: begin
        // Pretend we've received refill data and answer the read.
        rsp_d.rdata  = '0;
        rsp_d.rvalid = 1'b1;
        state_d      = IDLE;
      end

      default: state_d = IDLE;
    endcase
  end

  // Sequential: state, request latch, cache arrays, responses
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q   <= IDLE;
      rsp_q     <= '0;
      we_q      <= '0;
      wdata_q   <= '0;
      index_q   <= '0;
      tag_q     <= '0;

      for (int i = 0; i < NUM_LINES; i++) begin
        valid_array[i] <= 1'b0;
        tag_array[i]   <= '0;
        data_array[i]  <= '0;
      end
    end else begin
      state_q <= state_d;
      rsp_q   <= rsp_d;

      // Latch request parameters when we ACCEPT in IDLE
      if (state_q == IDLE && obi_req_i.req) begin
        we_q    <= obi_req_i.we;
        wdata_q <= obi_req_i.wdata;
        index_q <= index_c;
        tag_q   <= tag_c;
      end

      // MISS refill: mark line valid and fill with some data (here: zeros)
      if (state_q == MISS_WAIT) begin
        valid_array[index_q] <= 1'b1;
        tag_array[index_q]   <= tag_q;
        data_array[index_q]  <= '0;
      end

      // WRITE hit: write-through into local array
      if (state_q == LOOKUP && hit && we_q) begin
        data_array[index_q] <= wdata_q;
      end
    end
  end

  assign obi_rsp_o = rsp_q;

endmodule
