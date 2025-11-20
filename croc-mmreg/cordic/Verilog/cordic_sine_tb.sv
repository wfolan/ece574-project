// CORDIC Testbench
// Copyright (c) 2025 Worcester Polytechnic Institute
// Patrick Schaumont

module cordic_sine_tb;

    localparam int FRAC = 15;
    localparam logic signed [31:0] PI2 = 32'h0000_C90f;
    localparam int CLK_PERIOD = 10;

    // DUT
    logic clk;
    logic rst_n;
    logic start;
    logic signed [31:0] input_angle;
    logic signed [31:0] sine_out;
    logic valid;

    // Testbench variables
    logic signed [31:0] angle_step;
    logic signed [31:0] current_angle;
    int test_count;
    int error_count;
    real expected_sine;
    real computed_sine;
    real angle_radians;
    real error;
    real max_error;

    cordic_sine dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .input_angle(input_angle),
        .sine_out(sine_out),
        .valid(valid)
    );

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    function real fixed_to_real(logic signed [31:0] fixed_val);
        return $itor(fixed_val) / (2.0 ** FRAC);
    endfunction

    function logic signed [31:0] real_to_fixed(real real_val);
        return $rtoi(real_val * (2.0 ** FRAC));
    endfunction

   function real abs_real;
      input real val;
      begin
         if (val < 0.0)
           abs_real = -val;
         else
           abs_real = val;
      end
   endfunction

   initial begin
      rst_n = 0;
      start = 0;
      input_angle = 0;
      test_count = 0;
      error_count = 0;
      max_error = 0.0;

      angle_step = PI2 / 16;

      $display("\n========================================");
      $display("CORDIC Sine Function Testbench");
      $display("========================================");
      $display("Testing angles from 0 to 2*PI in steps of PI/16");
      $display("Clock Period: %0d ns", CLK_PERIOD);
      $display("Fixed-point format: <int,%0d>", FRAC);
      $display("========================================\n");

      #(CLK_PERIOD * 2);
      rst_n = 1;
      #(CLK_PERIOD * 2);

      for (int i = 0; i < 64; i++) begin
         current_angle = i * angle_step;

         input_angle = current_angle;
         start = 1;
         @(posedge clk);
         start = 0;

         wait(valid == 1);
         @(posedge clk);

         angle_radians = fixed_to_real(current_angle);
         expected_sine = $sin(angle_radians);
         computed_sine = fixed_to_real(sine_out);
         error = computed_sine - expected_sine;

         if (abs_real(error) > max_error)
           max_error = abs_real(error);

// a     0 s          2 ( sin( 0.00000) =  0.00006 ) sin  0.00000 err  0.000061035156250
// a   c90 s        c8a ( sin( 0.09814) =  0.09796 ) sin  0.09799 err -0.000025620938712

         if (abs_real(error) > 0.001) begin
            error_count++;
                        $display("a %8x s %8x ( sin ( %12.9f ) = %12.9f ) sin %12.9f err %12.9f ** ERROR",
                                         current_angle,
                                         sine_out,
                                         angle_radians,
                                         expected_sine,
                                         computed_sine,
                                         error);
         end else begin
                        $display("a %8x s %8x ( sin ( %12.9f ) = %12.9f ) sin %12.9f err %12.9f",
                                         current_angle,
                                         sine_out,
                                         angle_radians,
                                         expected_sine,
                                         computed_sine,
                                         error);
         end

         test_count++;

         repeat(3) @(posedge clk);
      end

      $display("\n========================================");
      $display("Test Summary");
      $display("========================================");
      $display("Total tests:     %0d", test_count);
      $display("Errors:          %0d", error_count);
      $display("Maximum error:   %12.9f", max_error);
      $display("Pass rate:       %0.2f%%", 100.0 * (test_count - error_count) / test_count);

      if (error_count == 0) begin
         $display("\n*** ALL TESTS PASSED ***\n");
      end else begin
         $display("\n*** %0d TESTS FAILED ***\n", error_count);
      end

      $display("========================================\n");

      #(CLK_PERIOD * 10);
      $finish;
   end

   initial begin
      #(CLK_PERIOD * 10000);
      $display("\n*** ERROR: Simulation timeout ***\n");
      $finish;
   end

   initial begin
      $dumpfile("cordic_sine_tb.vcd");
      $dumpvars(0, cordic_sine_tb);
   end

endmodule
