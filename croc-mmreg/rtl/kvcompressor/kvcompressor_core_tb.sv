`timescale 1ns/1ps

module kvcompressor_core_tb;

  // ---------------------------------------------------------------------------
  // Parameters
  // ---------------------------------------------------------------------------
  localparam int CLK_PERIOD = 10;
  localparam int MEM_WORDS  = 256;

  // ---------------------------------------------------------------------------
  // Clock and reset
  // ---------------------------------------------------------------------------
  logic clk;
  logic rst_ni;

  initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk; // 100 MHz
  end

  task automatic do_reset();
    begin
      rst_ni = 1'b0;
      repeat (5) @(posedge clk);
      rst_ni = 1'b1;
      @(posedge clk);
    end
  endtask

  // ---------------------------------------------------------------------------
  // DUT interface signals
  // ---------------------------------------------------------------------------
  // MMIO-like control inputs
  logic         start_i;
  logic [31:0]  scale_i;
  logic [31:0]  zp_i;
  logic         auto_scale_i;
  logic [31:0]  src_addr_i;
  logic [31:0]  dst_addr_i;
  logic [31:0]  length_i;

  // Status / IRQ
  logic         busy_o;
  logic         done_o;
  logic         irq_o;
  logic         int_en_i;

  // Memory master interface
  logic         mem_req_o;
  logic         mem_gnt_i;
  logic [31:0]  mem_addr_o;
  logic         mem_we_o;
  logic [3:0]   mem_be_o;
  logic [31:0]  mem_wdata_o;
  logic         mem_rvalid_i;
  logic [31:0]  mem_rdata_i;
  logic         mem_err_i;

  // ---------------------------------------------------------------------------
  // DUT instantiation
  // ---------------------------------------------------------------------------
  kvcompressor_core #(
    .VECTOR_MAX_LEN(512)
  ) dut (
    .clk_i        ( clk        ),
    .rst_ni       ( rst_ni     ),

    .start_i      ( start_i    ),
    .scale_i      ( scale_i    ),
    .zp_i         ( zp_i       ),
    .auto_scale_i ( auto_scale_i ),
    .src_addr_i   ( src_addr_i ),
    .dst_addr_i   ( dst_addr_i ),
    .length_i     ( length_i   ),

    .busy_o       ( busy_o     ),
    .done_o       ( done_o     ),

    .irq_o        ( irq_o      ),
    .int_en_i     ( int_en_i   ),

    .mem_req_o    ( mem_req_o  ),
    .mem_gnt_i    ( mem_gnt_i  ),
    .mem_addr_o   ( mem_addr_o ),
    .mem_we_o     ( mem_we_o   ),
    .mem_be_o     ( mem_be_o   ),
    .mem_wdata_o  ( mem_wdata_o ),
    .mem_rvalid_i ( mem_rvalid_i ),
    .mem_rdata_i  ( mem_rdata_i ),
    .mem_err_i    ( mem_err_i  )
  );

  // ---------------------------------------------------------------------------
  // Simple memory model (32-bit words, byte-addressed)
  // ---------------------------------------------------------------------------
  logic [31:0] mem [0:MEM_WORDS-1];

  // simple one-cycle-latency read protocol
  logic        pending_read;
  logic [31:0] pending_addr;

  // mem_err_i is always 0 (no error)
  assign mem_err_i = 1'b0;

  // Memory model
  always_ff @(posedge clk or negedge rst_ni) begin
    if (!rst_ni) begin
      mem_gnt_i     <= 1'b0;
      mem_rvalid_i  <= 1'b0;
      mem_rdata_i   <= 32'h0;
      pending_read  <= 1'b0;
      pending_addr  <= 32'h0;
    end else begin
      // default deassert
      mem_gnt_i    <= 1'b0;
      mem_rvalid_i <= 1'b0;

      // Handle new request
      if (mem_req_o) begin
        mem_gnt_i <= 1'b1;

        if (mem_we_o) begin
          // Write: full-word write, ignore byte enables for now
          mem[mem_addr_o[11:2]] <= mem_wdata_o;
          // For this DUT, WRITE_WAIT uses (!mem_err_i) so no need to assert rvalid
        end else begin
          // Read: schedule data for next cycle
          pending_read <= 1'b1;
          pending_addr <= mem_addr_o;
        end
      end

      // provide read data one cycle after request
      if (pending_read) begin
        mem_rvalid_i <= 1'b1;
        mem_rdata_i  <= mem[pending_addr[11:2]];
        pending_read <= 1'b0;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Helpers: initialize memory with INT16 samples and print memory
  // ---------------------------------------------------------------------------

  task automatic init_memory();
    int i;
    begin
      // Clear memory
      for (i = 0; i < MEM_WORDS; i++) begin
        mem[i] = 32'h0;
      end

      // Put a few known INT16 samples starting at src_addr_i = 0x0000_0000
      // We pack 2 x int16 per 32-bit word: {x1, x0}
      // Choose values that are within [-128, 127] so saturation doesn't kick in
      //
      // Samples: [10, -20, 50, -60]  (4 samples => length_i = 4)
      mem[0] = {16'shFFEC, 16'sh000A}; // x1=-20, x0=10
      mem[1] = {16'shFFC4, 16'sh0032}; // x1=-60, x0=50
    end
  endtask

  task automatic dump_memory_region(input [31:0] base_addr, input int words);
    int i;
    begin
      $display("---- Memory dump from 0x%08h (%0d words) ----", base_addr, words);
      for (i = 0; i < words; i++) begin
        $display("  [0x%08h] = 0x%08h",
                 base_addr + (i*4),
                 mem[(base_addr[11:2]) + i]);
      end
      $display("------------------------------------------------");
    end
  endtask

  // ---------------------------------------------------------------------------
  // Test bookkeeping (similar spirit to cordic_sine_tb)
  // ---------------------------------------------------------------------------
  int test_count;
  int error_count;

  int cycle_count;
  int mem_read_reqs;
  int mem_write_reqs;
  int mem_refills;

  // ---------------------------------------------------------------------------
  // Single test run helper
  // ---------------------------------------------------------------------------
  task automatic run_single_test(input int test_id);
    begin
      $display("\n----------------------------------------");
      $display("KV Compressor Test %0d", test_id);
      $display("----------------------------------------");

      // reset counters
     cycle_count     = 0;
     mem_read_reqs  = 0;
     mem_write_reqs = 0;
     mem_refills    = 0;

      // defaults
      start_i      = 1'b0;
      scale_i      = 32'd0;
      zp_i         = 32'd0;
      auto_scale_i = 1'b0;
      src_addr_i   = 32'h0000_0000;
      dst_addr_i   = 32'h0000_0100;
      length_i     = 32'd4;      // 4 INT16 samples (2 words)
      int_en_i     = 1'b0;

      do_reset();
      init_memory();

      $display("=== Before compression ===");
      dump_memory_region(32'h0000_0000, 2);  // src
      dump_memory_region(32'h0000_0100, 2);  // dst (should be 0)

      // Choose scale/zp so q ≈ x (no scaling) in PROCESS:
      // q = ((x * scale_q) >>> 15) + zp_q
      // -> with scale_q = 1<<15, zp_q = 0, q = x (then clamped to int8 range)
      scale_i      = 32'd32768;  // 1 << 15
      zp_i         = 32'd0;
      auto_scale_i = 1'b0;

      // Start compression
      @(posedge clk);
      start_i <= 1'b1;
      @(posedge clk);
      start_i <= 1'b0;

      // Wait for done_o
      wait(done_o == 1'b1);
      @(posedge clk);

      $display("=== After compression (done_o=1) ===");
      $display("busy_o = %0d, irq_o = %0d", busy_o, irq_o);
      dump_memory_region(32'h0000_0100, 2);  // dst

      // Simple check: at least one destination word must be non-zero
      if (mem[dst_addr_i[11:2]] == 32'h0) begin
        error_count++;
        $display("KV Test %0d ** ERROR: Destination memory word is still zero, compression may have failed.", test_id);
      end else begin
        $display("KV Test %0d PASS: Destination memory word at 0x%08h = 0x%08h",
                 test_id,
                 dst_addr_i,
                 mem[dst_addr_i[11:2]]);
      end

      $display("Activity summary for test %0d:", test_id);
      $display("  Total cycles      : %0d", cycle_count);
      $display("  Mem read requests : %0d", mem_read_reqs);
      $display("  Mem write requests: %0d", mem_write_reqs);
      $display("  Mem refills       : %0d", mem_refills);

      test_count++;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Main test sequence
  // ---------------------------------------------------------------------------
  initial begin
    test_count  = 0;
    error_count = 0;

    $display("\n========================================");
    $display("KV Compressor Core Testbench");
    $display("========================================");
    $display("CLK Period: %0d ns", CLK_PERIOD);
    $display("Memory size: %0d words (32-bit)", MEM_WORDS);
    $display("========================================\n");

    // For now we just run one functional test scenario.
    // You can clone this call with different source data or lengths later.
    run_single_test(0);

    // Summary
    $display("\n========================================");
    $display("KV Compressor Test Summary");
    $display("========================================");
    $display("Total tests: %0d", test_count);
    $display("Errors:      %0d", error_count);
    if (test_count > 0) begin
      real pass_rate;
      pass_rate = 100.0 * (test_count - error_count) / test_count;
      $display("Pass rate:   %0.2f%%", pass_rate);
    end

    if (error_count == 0) begin
      $display("\n*** ALL TESTS PASSED ***\n");
    end else begin
      $display("\n*** %0d TESTS FAILED ***\n", error_count);
    end

    $display("========================================\n");

    #(CLK_PERIOD * 10);
    $finish;
  end

  // ---------------------------------------------------------------------------
  // Timeout protection (like in cordic_sine_tb)
  // ---------------------------------------------------------------------------
  initial begin
    #(CLK_PERIOD * 100000);
    $display("\n*** ERROR: Simulation timeout in kvcompressor_core_tb ***\n");
    $finish;
  end

  // ---------------------------------------------------------------------------
  // VCD dump
  // ---------------------------------------------------------------------------
  initial begin
    $dumpfile("kvcompressor_core_tb.vcd");
    $dumpvars(0, kvcompressor_core_tb);
  end

// Summarized activity monitor (no per-cycle prints)
always @(posedge clk) begin
  if (rst_ni) begin
    cycle_count++;

    if (mem_req_o && !mem_we_o)
      mem_read_reqs++;

    if (mem_req_o && mem_we_o)
      mem_write_reqs++;

    if (mem_rvalid_i)
      mem_refills++;
  end
end

// Debug monitor: show FSM state and memory handshakes
`ifdef DEBUG_MONITOR
always @(posedge clk) begin
  $display("t=%0t  state=%0d  mem_req=%0b mem_gnt=%0b mem_rvalid=%0b  done=%0b busy=%0b",
           $time,
           dut.state_q,    // internal FSM state in kvcompressor_core
           mem_req_o,
           mem_gnt_i,
           mem_rvalid_i,
           done_o,
           busy_o);
end
`endif

endmodule