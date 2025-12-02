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

    // -----------------------------
    // FSM State Declaration
    // -----------------------------
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

    // -------------------------------------
    // Internal registers
    // -------------------------------------
    logic [31:0] element_count_q, element_count_d;

    // auto-scale accumulators
    logic signed [15:0] min_q, max_q, min_d, max_d;

    // quantization parameters
    logic [31:0] scale_q, scale_d;
    logic [31:0] zp_q, zp_d;

    // packer buffer (4 × int8 → one 32-bit word)
    logic [1:0]  packer_count_q, packer_count_d;
    logic [31:0] packer_q, packer_d;

    // memory address offset
    logic [31:0] src_offset_q, src_offset_d;
    logic [31:0] dst_offset_q, dst_offset_d;

    // extracted samples
    logic signed [15:0] x0, x1;

    // *** NEW: pre-decode mem_rdata_i outside always_comb ***
    logic signed [15:0] x0_from_mem, x1_from_mem;
    assign x0_from_mem = mem_rdata_i[15:0];
    assign x1_from_mem = mem_rdata_i[31:16];

    // *** NEW: pre-extract lower 16 bits of packer_q outside always_comb ***
    logic [15:0] packer_low16;
    assign packer_low16 = packer_q[15:0];

    // -------------------------------------
    // Default outputs + FSM
    // -------------------------------------
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
        state_d         = state_q;
        element_count_d = element_count_q;

        src_offset_d = src_offset_q;
        dst_offset_d = dst_offset_q;

        min_d = min_q;
        max_d = max_q;

        scale_d = scale_q;
        zp_d    = zp_q;

        packer_d       = packer_q;
        packer_count_d = packer_count_q;

        x0 = x0; // keep current by default
        x1 = x1;

        // -----------------------------
        // FSM Logic
        // -----------------------------
        case (state_q)

            // ============================================================
            // IDLE
            // ============================================================
            IDLE: begin
                if (start_i) begin
                    state_d = LOAD_SCALE;

                    // initialize remaining-element counter to total length
                    element_count_d = length_i;
                    src_offset_d    = 0;
                    dst_offset_d    = 0;

                    packer_d       = 0;
                    packer_count_d = 0;

                    if (auto_scale_i) begin
                        min_d = 16'sh7FFF;
                        max_d = -16'sh8000;
                    end
                end
            end

            // ============================================================
            // LOAD_SCALE
            // ============================================================
            LOAD_SCALE: begin
                if (!auto_scale_i) begin
                    scale_d = scale_i;
                    zp_d    = zp_i;
                    state_d = READ_REQ;
                end else begin
                    // auto-scale mode → need a min/max first pass
                    state_d = READ_REQ;
                end
            end

            // ============================================================
            // READ_REQ
            // ============================================================
            READ_REQ: begin
                mem_req_o  = 1'b1;
                mem_addr_o = src_addr_i + src_offset_q;
                mem_we_o   = 1'b0;

                if (mem_gnt_i)
                    state_d = READ_WAIT;
            end

            // ============================================================
            // READ_WAIT
            // ============================================================
            READ_WAIT: begin
                if (mem_rvalid_i) begin
                    // extract INT16 samples (no constant selects in always_comb)
                    x0 = x0_from_mem;
                    x1 = x1_from_mem;

                    // we treat element_count_q as "elements remaining"
                    // we just consumed 2 more INT16 samples
                    if (element_count_q > 32'd2)
                        element_count_d = element_count_q - 32'd2;
                    else
                        element_count_d = 32'd0;

                    src_offset_d = src_offset_q + 32'd4;

                    if (auto_scale_i) begin
                        // update min/max
                        min_d = (x0 < min_q) ? x0 : min_q;
                        min_d = (x1 < min_d) ? x1 : min_d;

                        max_d = (x0 > max_q) ? x0 : max_q;
                        max_d = (x1 > max_d) ? x1 : max_d;
                    end

                    // last element?
                    if (element_count_d == 0) begin
                        if (auto_scale_i)
                            state_d = CALC_SCALE;
                        else
                            state_d = PROCESS;

                        // for a possible second pass in auto-scale mode,
                        // restart src_offset at 0; element_count_d will be
                        // reinitialized in CALC_SCALE or kept as 0 for PROCESS
                        src_offset_d = 32'd0;
                    end else begin
                        state_d = READ_REQ;
                    end
                end
            end

            // ============================================================
            // CALC_SCALE
            // ============================================================
            CALC_SCALE: begin
                logic signed [15:0] absmax;
                absmax = (max_q > -min_q) ? max_q : -min_q;

                scale_d = 32'(127) / absmax;
                zp_d    = 32'(128);

                // reinitialize remaining-element counter for second pass
                element_count_d = length_i;
                src_offset_d    = 32'd0;

                state_d = READ_REQ;
            end

            // ============================================================
            // PROCESS (INT16 → INT8 quant + pack)
            // ============================================================
            PROCESS: begin
                // perform quantization
                logic signed [7:0] q0, q1;

                q0 = ((x0 * scale_q) >>> 15) + zp_q;
                q1 = ((x1 * scale_q) >>> 15) + zp_q;

                // clamp to [-128, 127]
                if (q0 > 127)  q0 = 127;
                if (q0 < -128) q0 = -128;
                if (q1 > 127)  q1 = 127;
                if (q1 < -128) q1 = -128;

                // ---------- packer logic WITHOUT bit selects in always_comb ----------
                // lower 16 bits come from packer_low16 (assigned outside)
                packer_d       = { q0, q1, packer_low16 };
                packer_count_d = packer_count_q + 2;

                // element_count_q now means "elements remaining"
                // we do NOT modify it here; it is only updated in READ_WAIT

                // need to write?
                // If we've packed 4 bytes OR there are no elements left,
                // request a write.
                if (packer_count_d == 4 || element_count_q == 0) begin
                    state_d = WRITE_REQ;
                end else begin
                    state_d = READ_REQ;
                end
            end

            // ============================================================
            // WRITE_REQ
            // ============================================================
            WRITE_REQ: begin
                mem_req_o   = 1'b1;
                mem_we_o    = 1'b1;
                mem_addr_o  = dst_addr_i + dst_offset_q;
                mem_wdata_o = packer_q;

                if (mem_gnt_i)
                    state_d = WRITE_WAIT;
            end

            // ============================================================
            // WRITE_WAIT
            // ============================================================
            WRITE_WAIT: begin
                if (mem_rvalid_i || !mem_err_i) begin
                    dst_offset_d    = dst_offset_q + 4;
                    packer_d        = 0;
                    packer_count_d  = 0;

                    // If no elements remain, we are done; otherwise, keep reading.
                    if (element_count_q == 0)
                        state_d = FINISH;
                    else
                        state_d = READ_REQ;
                end
            end

            // ============================================================
            // FINISH
            // ============================================================
            FINISH: begin
                done_o = 1'b1;
                if (int_en_i)
                    irq_o = 1'b1;

                if (!start_i)
                    state_d = IDLE;
            end
        endcase
    end


    // Sequential state + register update
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q         <= IDLE;
            element_count_q <= 0;
            src_offset_q    <= 0;
            dst_offset_q    <= 0;

            scale_q <= 0;
            zp_q    <= 0;

            packer_q       <= 0;
            packer_count_q <= 0;

            min_q <= 0;
            max_q <= 0;

            x0 <= 0;
            x1 <= 0;
        end else begin
            state_q         <= state_d;
            element_count_q <= element_count_d;
            src_offset_q    <= src_offset_d;
            dst_offset_q    <= dst_offset_d;

            scale_q <= scale_d;
            zp_q    <= zp_d;

            min_q <= min_d;
            max_q <= max_d;

            packer_q       <= packer_d;
            packer_count_q <= packer_count_d;

            x0 <= x0; // already updated in combinational
            x1 <= x1;
        end
    end

endmodule