// -----------------------------------------------------------------------------
// kvcompressor_core.sv
// Tiny KV-Cache INT16 → INT8 Compressor
// FSM + datapath controller
// -----------------------------------------------------------------------------

module kvcompressor_core #(
    parameter int VECTOR_MAX_LEN = 512
)(
    input  logic         clk_i,
    input  logic         rst_ni,

    // MMIO Register Inputs
    input  logic         start_i,
    input  logic  [31:0] scale_i,
    input  logic  [31:0] zp_i,
    input  logic         auto_scale_i,
    input  logic  [31:0] src_addr_i,
    input  logic  [31:0] dst_addr_i,
    input  logic  [31:0] length_i,          // number of INT16 samples

    // Status Outputs
    output logic         busy_o,
    output logic         done_o,

    // Interrupt
    output logic         irq_o,
    input  logic         int_en_i,

    // Memory Master OBI Interface
    output logic         mem_req_o,
    input  logic         mem_gnt_i,
    output logic [31:0]  mem_addr_o,
    output logic         mem_we_o,
    output logic [3:0]   mem_be_o,
    output logic [31:0]  mem_wdata_o,
    input  logic         mem_rvalid_i,
    input  logic [31:0]  mem_rdata_i,
    input  logic         mem_err_i
);

    // FSM State Declaration
    typedef enum logic [3:0] {
        IDLE        = 4'd0,
        LOAD_SCALE  = 4'd1,
        READ_REQ    = 4'd2,
        READ_WAIT   = 4'd3,
        CALC_SCALE  = 4'd4,
        PROCESS     = 4'd5,
        WRITE_REQ   = 4'd6,
        WRITE_WAIT  = 4'd7,
        FINISH      = 4'd8
    } state_e;

    state_e state_q, state_d;

    // Internal registers
    logic [31:0] element_count_q, element_count_d;

    // auto-scale accumulators (first pass)
    logic signed [15:0] min_q, min_d;
    logic signed [15:0] max_q, max_d;

    // whether we are currently in the first pass for auto-scale
    logic auto_scale_pass1_q, auto_scale_pass1_d;

    // quantization parameters
    logic [31:0] scale_q, scale_d;  // Q15 fixed-point scale
    logic [31:0] zp_q, zp_d;        // zero-point (usually 0 for symmetric int8)

    // packer buffer (4 × int8 → one 32-bit word)
    logic [1:0]  packer_count_q, packer_count_d;
    logic [31:0] packer_q, packer_d;

    // memory address offsets
    logic [31:0] src_offset_q, src_offset_d;
    logic [31:0] dst_offset_q, dst_offset_d;

    // extracted samples
    logic signed [15:0] x0, x1;

    // Default outputs + FSM
    always_comb begin
        // defaults
        mem_req_o   = 1'b0;
        mem_we_o    = 1'b0;
        mem_be_o    = 4'hF;
        mem_addr_o  = 32'h0;
        mem_wdata_o = packer_q;

        done_o = 1'b0;
        busy_o = (state_q != IDLE && state_q != FINISH);
        irq_o  = 1'b0;

        // next-state defaults
        state_d          = state_q;
        element_count_d  = element_count_q;

        src_offset_d = src_offset_q;
        dst_offset_d = dst_offset_q;

        min_d = min_q;
        max_d = max_q;

        auto_scale_pass1_d = auto_scale_pass1_q;

        scale_d = scale_q;
        zp_d    = zp_q;

        packer_d       = packer_q;
        packer_count_d = packer_count_q;

        // FSM Logic
        unique case (state_q)

            // IDLE
            IDLE: begin
                if (start_i) begin
                    state_d = LOAD_SCALE;

                    element_count_d = 32'd0;
                    src_offset_d    = 32'd0;
                    dst_offset_d    = 32'd0;

                    packer_d       = 32'd0;
                    packer_count_d = 2'd0;

                    // latch whether we will do auto-scale
                    auto_scale_pass1_d = auto_scale_i;

                    if (auto_scale_i) begin
                        // initialize min/max for first pass
                        min_d = 16'sh7FFF;
                        max_d = -16'sh8000;
                    end else begin
                        min_d = 16'sd0;
                        max_d = 16'sd0;
                    end
                end
            end

            // LOAD_SCALE
            LOAD_SCALE: begin
                if (!auto_scale_i) begin
                    // manual mode: use programmed scale/zp
                    scale_d = scale_i;
                    zp_d    = zp_i;
                    state_d = READ_REQ;
                end else begin
                    // auto-scale mode → need a min/max first pass
                    state_d = READ_REQ;
                end
            end

            // READ_REQ
            READ_REQ: begin
                mem_req_o  = 1'b1;
                mem_addr_o = src_addr_i + src_offset_q;
                mem_we_o   = 1'b0;

                if (mem_gnt_i)
                    state_d = READ_WAIT;
            end

            // READ_WAIT
            READ_WAIT: begin
                if (mem_rvalid_i) begin
                    // extract INT16 samples
                    x0 = mem_rdata_i[15:0];
                    x1 = mem_rdata_i[31:16];

                    element_count_d = element_count_q + 32'd2;
                    src_offset_d    = src_offset_q + 32'd4;

                    if (auto_scale_pass1_q) begin
                        // first pass: update min/max
                        logic signed [15:0] tmp_min;
                        logic signed [15:0] tmp_max;

                        tmp_min = (x0 < min_q) ? x0 : min_q;
                        tmp_min = (x1 < tmp_min) ? x1 : tmp_min;

                        tmp_max = (x0 > max_q) ? x0 : max_q;
                        tmp_max = (x1 > tmp_max) ? x1 : tmp_max;

                        min_d = tmp_min;
                        max_d = tmp_max;
                    end

                    // last element of this pass?
                    if (element_count_d >= length_i) begin
                        element_count_d = 32'd0;
                        src_offset_d    = 32'd0;

                        if (auto_scale_pass1_q) begin
                            // end of first pass in auto-scale mode
                            state_d = CALC_SCALE;
                        end else begin
                            // normal processing pass
                            state_d = PROCESS;
                        end
                    end else begin
                        // continue streaming
                        state_d = READ_REQ;
                    end
                end
            end

            // CALC_SCALE
            CALC_SCALE: begin
                // Compute symmetric range based on min/max from pass 1
                logic signed [15:0] abs_min;
                logic signed [15:0] abs_max;

                // |min_q|
                abs_min = (min_q < 0) ? -min_q : min_q;

                // abs_max = max(|min_q|, max_q)
                abs_max = (max_q > abs_min) ? max_q : abs_min;

                if (abs_max == 0) begin
                    // Degenerate case: all zeros
                    scale_d = 32'd0;
                end else begin
                    // Q15 fixed-point scale:
                    // scale_real = 127 / abs_max
                    // scale_q    = round(scale_real * 2^15)
                    //           = (127 << 15) / abs_max
                    scale_d = (32'(127) <<< 15) / abs_max;
                end

                // Symmetric signed int8 → zero point = 0
                zp_d = 32'sd0;

                // Finished first pass
                auto_scale_pass1_d = 1'b0;

                // Reset counters and offsets for second pass
                element_count_d = 32'd0;
                src_offset_d    = 32'd0;
                dst_offset_d    = 32'd0;

                // Go back to READ_REQ for quantizing pass
                state_d = READ_REQ;
            end

            // PROCESS (INT16 → INT8 quant + pack)
            PROCESS: begin
                // perform quantization
                logic signed [7:0] q0, q1;

                // x * scale_q is Q(16+15) → shift back by 15
                q0 = (x0 * $signed(scale_q)) >>> 15;
                q1 = (x1 * $signed(scale_q)) >>> 15;

                // apply zero-point (useful if non-zero ZP in manual mode)
                q0 = q0 + $signed(zp_q[7:0]);
                q1 = q1 + $signed(zp_q[7:0]);

                // clamp to [-128, 127]
                if (q0 > 127)  q0 = 127;
                if (q0 < -128) q0 = -128;
                if (q1 > 127)  q1 = 127;
                if (q1 < -128) q1 = -128;

                // packer logic: shift existing bytes down and insert new ones at MSB side
                packer_d = (packer_q >> 8);
                packer_d[31:24] = q0;
                packer_d[23:16] = q1;
                packer_count_d  = packer_count_q + 2;

                element_count_d = element_count_q + 2;

                // need to write?
                if (packer_count_d == 4 || element_count_d >= length_i) begin
                    state_d = WRITE_REQ;
                end else begin
                    state_d = READ_REQ;
                end
            end

            // WRITE_REQ
            WRITE_REQ: begin
                mem_req_o   = 1'b1;
                mem_we_o    = 1'b1;
                mem_addr_o  = dst_addr_i + dst_offset_q;
                mem_wdata_o = packer_q;

                if (mem_gnt_i)
                    state_d = WRITE_WAIT;
            end

            // WRITE_WAIT
            WRITE_WAIT: begin
                // simple "write accepted" model; tools may refine this
                if (mem_rvalid_i || !mem_err_i) begin
                    dst_offset_d    = dst_offset_q + 32'd4;
                    packer_d        = 32'd0;
                    packer_count_d  = 2'd0;

                    if (element_count_q >= length_i)
                        state_d = FINISH;
                    else
                        state_d = READ_REQ;
                end
            end

            // FINISH
            FINISH: begin
                done_o = 1'b1;
                if (int_en_i)
                    irq_o = 1'b1;

                if (!start_i)
                    state_d = IDLE;
            end

            default: begin
                state_d = IDLE;
            end
        endcase
    end

    // Sequential state + register update
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q           <= IDLE;
            element_count_q   <= 32'd0;
            src_offset_q      <= 32'd0;
            dst_offset_q      <= 32'd0;

            scale_q           <= 32'd0;
            zp_q              <= 32'd0;

            packer_q          <= 32'd0;
            packer_count_q    <= 2'd0;

            min_q             <= 16'sd0;
            max_q             <= 16'sd0;
            auto_scale_pass1_q <= 1'b0;
        end else begin
            state_q           <= state_d;
            element_count_q   <= element_count_d;
            src_offset_q      <= src_offset_d;
            dst_offset_q      <= dst_offset_d;

            scale_q           <= scale_d;
            zp_q              <= zp_d;

            min_q             <= min_d;
            max_q             <= max_d;
            auto_scale_pass1_q <= auto_scale_pass1_d;

            packer_q          <= packer_d;
            packer_count_q    <= packer_count_d;
        end
    end

endmodule
