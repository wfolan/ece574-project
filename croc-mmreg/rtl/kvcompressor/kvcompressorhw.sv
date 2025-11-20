// kvcomp_hw.sv
`include "kvcompressorhw_pkg.sv"

module kvcomp_hw #(
  parameter int ADDR_WIDTH = 4  // word-addressable region (e.g., 0x00..0x1C)
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,

  // User OBI / MMIO slave interface (adapt names to your Croc user bus)
  input  logic                  req_i,
  output logic                  gnt_o,
  input  logic [ADDR_WIDTH-1:0] addr_i,
  input  logic                  we_i,
  input  logic [3:0]            be_i,
  input  logic [31:0]           wdata_i,
  output logic [31:0]           rdata_o,
  output logic                  rvalid_o,

  // Optional error output (unused here)
  output logic                  err_o
);

  import kvcomp_hw_pkg::*;

  // Register file
  kvcomp_regs_t regs_q, regs_d;

  // Decode word index (word-aligned)
  logic [$clog2(KVCOMP_NUM_WORDS)-1:0] word_idx;
  assign word_idx = addr_i[ADDR_WIDTH-1:2];

  // Handshake
  logic req_q, req_d;
  logic rvalid_d;

  // Core connections
  logic                    start_pulse;
  kvcomp_ctrl_t            ctrl_q;
  kvcomp_status_t          status_q;
  logic                    sample_valid;
  logic [15:0]             sample_in;
  logic [7:0]              sample_out;
  logic                    q_valid;
  logic                    busy, done, err;

  // Cast view of CTRL / STATUS
  always_comb begin
    ctrl_q   = kvcomp_ctrl_t'(regs_q.ctrl);
    status_q = kvcomp_status_t'(regs_q.status);
  end

  // -------------------------------------------
  // Core instance
  // -------------------------------------------
  kvcomp_core u_core (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),

    .start_i        (start_pulse),
    .len_i          (regs_q.len[15:0]),
    .scale_i        (regs_q.scale[15:0]),
    .zp_i           (regs_q.zp[7:0]),
    .mode_k_ch_i    (ctrl_q.mode_k_ch),
    .clamp_en_i     (ctrl_q.clamp_en),

    .sample_i       (sample_in),
    .sample_valid_i (sample_valid),

    .q_sample_o     (sample_out),
    .q_valid_o      (q_valid),

    .busy_o         (busy),
    .done_o         (done),
    .err_o          (err)
  );

  assign sample_in = regs_q.in_data[15:0];

  // Generate start pulse when SW writes CTRL.start = 1 and it was 0
  // Hardware clears the bit after consuming it.
  always_comb begin
    start_pulse = 1'b0;
    // default mirror of regs
    regs_d      = regs_q;

    // Default STATUS update from core
    kvcomp_status_t status_d = status_q;
    status_d.busy      = busy;
    status_d.err       = err;
    // "done" is sticky until SW clears it by writing STATUS
    if (done) begin
      status_d.done    = 1'b1;
    end
    // out_valid pulses when new output appears
    status_d.out_valid = q_valid;

    regs_d.status = status_d;

    // When q_valid is high, capture the result into OUT_DATA
    if (q_valid) begin
      regs_d.out_data[7:0]  = sample_out;
      regs_d.out_data[31:8] = '0;
    end

    // MMIO write handling
    if (req_i && we_i) begin
      unique case (word_idx)
        KVCOMP_CTRL_IDX: begin
          // Allow SW to update all bits; HW will interpret start bit
          regs_d.ctrl = wdata_i;
        end
        KVCOMP_LEN_IDX: begin
          regs_d.len  = wdata_i;
        end
        KVCOMP_SCALE_IDX: begin
          regs_d.scale = wdata_i;
        end
        KVCOMP_ZP_IDX: begin
          regs_d.zp = wdata_i;
        end
        KVCOMP_IN_DATA_IDX: begin
          regs_d.in_data = wdata_i;
          // Writing IN_DATA produces a sample_valid pulse
        end
        KVCOMP_OUT_DATA_IDX: begin
          // Read-only in HW; ignore writes
        end
        KVCOMP_STATUS_IDX: begin
          // SW can clear 'done' and 'err' by writing STATUS
          regs_d.status = wdata_i;
        end
        default: ;
      endcase
    end

    // start_pulse logic: rising edge of CTRL.start
    kvcomp_ctrl_t ctrl_d = kvcomp_ctrl_t'(regs_d.ctrl);
    kvcomp_ctrl_t ctrl_prev = kvcomp_ctrl_t'(regs_q.ctrl);

    if (!ctrl_prev.start && ctrl_d.start) begin
      start_pulse = 1'b1;
    end

    // Hardware clears start once we’ve consumed it
    if (start_pulse) begin
      ctrl_d.start = 1'b0;
      regs_d.ctrl  = ctrl_d;
    end
  end

  // Sample valid when SW writes IN_DATA while core is RUNning
  assign sample_valid = (req_i && we_i && (word_idx == KVCOMP_IN_DATA_IDX));

  // -------------------------------------------
  // Simple 1-cycle response MMIO slave
  // (very similar to a trimmed-down cordichw)
  // -------------------------------------------
  always_comb begin
    gnt_o    = 1'b0;
    rdata_o  = '0;
    rvalid_d = 1'b0;
    err_o    = 1'b0;
    req_d    = req_q;

    if (req_i) begin
      gnt_o = 1'b1;
      if (!we_i) begin
        // Read
        unique case (word_idx)
          KVCOMP_CTRL_IDX:     rdata_o = regs_q.ctrl;
          KVCOMP_LEN_IDX:      rdata_o = regs_q.len;
          KVCOMP_SCALE_IDX:    rdata_o = regs_q.scale;
          KVCOMP_ZP_IDX:       rdata_o = regs_q.zp;
          KVCOMP_IN_DATA_IDX:  rdata_o = regs_q.in_data;
          KVCOMP_OUT_DATA_IDX: rdata_o = regs_q.out_data;
          KVCOMP_STATUS_IDX:   rdata_o = regs_q.status;
          default:             rdata_o = '0;
        endcase
        rvalid_d = 1'b1;
      end
      // Writes are already handled combinationally in regs_d
    end
  end

  // Sequential registers + handshake
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      regs_q    <= '0;
      req_q     <= 1'b0;
      rvalid_o  <= 1'b0;
    end else begin
      regs_q    <= regs_d;
      req_q     <= req_d;
      rvalid_o  <= rvalid_d;
    end
  end

endmodule
