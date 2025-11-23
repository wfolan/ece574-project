// tiny_cache.sv
// Direct-mapped word cache as an OBI subordinate on user_sbr.
// - 1 word per line (LINE_BYTES = 4)
// - Direct-mapped
// - FSM with IDLE, LOOKUP, MISS_REQ, MISS_WAIT
// - Read hit: return cached word
// - Read miss: return 0 and allocate a zero-filled line
// - Write: write-allocate/update line (hit or miss) with byte enables

module tiny_cache
  import croc_pkg::*;
  import user_pkg::*;
  #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = SbrObiCfg.DataWidth,
    parameter int unsigned LINE_BYTES = 4,    // 1 word per line
    parameter int unsigned NUM_LINES  = 64    // number of cache lines
  ) (
    input  logic       clk_i,
    input  logic       rst_ni,

    // OBI subordinate interface (from user_domain obi_demux)
    input  sbr_obi_req_t obi_req_i,
    output sbr_obi_rsp_t obi_rsp_o
  );

  // Helper: integer ceiling(log2()) without using $clog2
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

  // Address breakdown: [ TAG | INDEX | WORD_OFFSET ]
  localparam int unsigned OFFSET_BITS = clog2_int(LINE_BYTES);   // word offset
  localparam int unsigned INDEX_BITS  = clog2_int(NUM_LINES);    // line index
  localparam int unsigned TAG_WIDTH   = ADDR_WIDTH - OFFSET_BITS - INDEX_BITS;

  // Combinational index/tag from current request address
  logic [INDEX_BITS-1:0] index_c;
  logic [TAG_WIDTH-1:0]  tag_c;

  assign index_c = obi_req_i.a.addr[OFFSET_BITS + INDEX_BITS - 1 : OFFSET_BITS];
  assign tag_c   = obi_req_i.a.addr[ADDR_WIDTH-1 : OFFSET_BITS + INDEX_BITS];

  // Latched index/tag (for the accepted request)
  logic [INDEX_BITS-1:0] index_q;
  logic [TAG_WIDTH-1:0]  tag_q;

  // Tag / valid / data arrays
  logic [TAG_WIDTH-1:0]  tag_array   [NUM_LINES-1:0];
  logic                  valid_array [NUM_LINES-1:0];
  logic [DATA_WIDTH-1:0] data_array  [NUM_LINES-1:0];

  // Latched request info
  logic                   we_q;
  logic [DATA_WIDTH-1:0]  wdata_q;
  logic [DATA_WIDTH/8-1:0] be_q;

  // FSM: IDLE → LOOKUP → [HIT => IDLE | MISS => MISS_REQ → MISS_WAIT → IDLE]
  typedef enum logic [1:0] {
    IDLE      = 2'd0,
    LOOKUP    = 2'd1,
    MISS_REQ  = 2'd2,
    MISS_WAIT = 2'd3
  } cache_state_e;

  cache_state_e state_q, state_d;

  // Hit/miss logic (based on latched index/tag)
  logic                  hit;
  logic [DATA_WIDTH-1:0] line_data;

  assign line_data = data_array[index_q];
  assign hit       = valid_array[index_q] && (tag_array[index_q] == tag_q);

  // Registered response
  sbr_obi_rsp_t rsp_q, rsp_d;

  // Combinational FSM + response
  always_comb begin
    // Default response: no grant, no read data, no error
    rsp_d     = '0;
    rsp_d.err = 1'b0;

    state_d = state_q;

    unique case (state_q)

      // IDLE: wait for a request; accept and go to LOOKUP
      IDLE: begin
        if (obi_req_i.req) begin
          rsp_d.gnt = 1'b1;  // accept request this cycle
          state_d   = LOOKUP;
        end
      end

      // LOOKUP: tag compare
      //  - HIT:
      //      * READ: return data now (rvalid=1, rdata=line_data)
      //      * WRITE: just update in seq block, no rvalid
      //    then → IDLE
      //  - MISS:
      //      * go to MISS_REQ
      LOOKUP: begin
        if (hit) begin
          if (!we_q) begin
            rsp_d.rvalid = 1'b1;
            rsp_d.rdata  = line_data;
          end
          state_d = IDLE;
        end else begin
          // miss → perform a multi-cycle "refill"
          state_d = MISS_REQ;
        end
      end

      // MISS_REQ: this is where you'd start a backing memory
      // request in a larger design; here we just model an extra
      // cycle of miss latency and go to MISS_WAIT.
      MISS_REQ: begin
        state_d = MISS_WAIT;
      end

      // MISS_WAIT: "refill" the line and respond
      //  - READ miss: rvalid=1, rdata=0 (we filled with zeros)
      //  - WRITE miss: line will be filled with wdata in seq block
      MISS_WAIT: begin
        if (!we_q) begin
          rsp_d.rvalid = 1'b1;
          rsp_d.rdata  = '0;   // stub refill data
        end
        state_d = IDLE;
      end

      default: begin
        state_d = IDLE;
      end
    endcase
  end

  // Sequential: state, response, and cache array updates
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= IDLE;
      rsp_q   <= '0;

      we_q    <= 1'b0;
      wdata_q <= '0;
      be_q    <= '0;
      index_q <= '0;
      tag_q   <= '0;

      for (int i = 0; i < NUM_LINES; i++) begin
        valid_array[i] <= 1'b0;
        tag_array[i]   <= '0;
        data_array[i]  <= '0;
      end
    end else begin
      state_q <= state_d;
      rsp_q   <= rsp_d;

      // Latch request info when we accept it in IDLE
      if (state_q == IDLE && obi_req_i.req) begin
        we_q    <= obi_req_i.we;
        wdata_q <= obi_req_i.wdata;
        be_q    <= obi_req_i.be;

        index_q <= index_c;
        tag_q   <= tag_c;
      end

      // Data-path updates depending on state

      // Write hit logic in LOOKUP
      if (state_q == LOOKUP && hit && we_q) begin
        logic [DATA_WIDTH-1:0] new_data;
        new_data = data_array[index_q];

        for (int b = 0; b < DATA_WIDTH/8; b++) begin
          if (be_q[b]) begin
            new_data[b*8 +: 8] = wdata_q[b*8 +: 8];
          end
        end

        data_array[index_q]  <= new_data;
        tag_array[index_q]   <= tag_q;
        valid_array[index_q] <= 1'b1;
      end

      // Miss refill / write-miss allocate in MISS_WAIT
      if (state_q == MISS_WAIT) begin
        logic [DATA_WIDTH-1:0] new_data;

        if (we_q) begin
          // Write miss: allocate and store wdata with byte enables
          new_data = data_array[index_q];
          for (int b = 0; b < DATA_WIDTH/8; b++) begin
            if (be_q[b]) begin
              new_data[b*8 +: 8] = wdata_q[b*8 +: 8];
            end
          end
        end else begin
          // Read miss: allocate zero-filled line
          new_data = '0;
        end

        data_array[index_q]  <= new_data;
        tag_array[index_q]   <= tag_q;
        valid_array[index_q] <= 1'b1;
      end
    end
  end

  // Drive OBI response
  assign obi_rsp_o = rsp_q;

endmodule
