// -----------------------------------------------------------------------------
// kvcompressor_mmreg.sv
// Self-contained MMIO register block for KV Compressor
// Contains register offsets + struct + MMREG wiring
// -----------------------------------------------------------------------------

module kvcompressor_mmreg
  import croc_pkg::*;
  import user_pkg::*;
  import mmreg_pkg::*;    // generic MMREG engine
(
    input  logic         clk_i,
    input  logic         rst_ni,

    // MMIO (OBI subordinate)
    input  sbr_obi_req_t obi_req_i,
    output sbr_obi_rsp_t obi_rsp_o,

    // Signals feed to to kvcompressor_core
    output logic         start_o,
    output logic         auto_scale_o,
    output logic         int_en_o,

    output logic [31:0]  src_addr_o,
    output logic [31:0]  dst_addr_o,
    output logic [31:0]  length_o,
    output logic [31:0]  scale_o,
    output logic [31:0]  zp_o,

    // Inputs from kvcompressor_core
    input  logic         busy_i,
    input  logic         done_i,
    input  logic         irq_i
);

    // LOCAL REGISTER DEFINITIONS
    localparam int RegWidth = 32;

    typedef enum int unsigned {
        REG_CTRL      = 0,
        REG_LEN       = 1,
        REG_SRC_ADDR  = 2,
        REG_DST_ADDR  = 3,
        REG_SCALE     = 4,
        REG_ZP        = 5,
        REG_STATUS    = 6,
        NUM_REGS      = 7
    } kvreg_e;

    //storage structure for registers
    typedef struct packed {
        logic [RegWidth-1:0] reg [NUM_REGS];
    } kv_mmreg_reg_t;

    // Register storage
    kv_mmreg_reg_t kv_regs_q, kv_regs_d;

    // Instantiate generic MMREG logic
    mmreg #(
        .obi_req_t (sbr_obi_req_t),
        .obi_rsp_t (sbr_obi_rsp_t)
    ) i_mmreg (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .obi_req_i (obi_req_i),
        .obi_rsp_o (obi_rsp_o),

        // Forward register array
        .reg_q     (kv_regs_q),   // storage
        .reg_d     (kv_regs_d)    // next-state
    );

    // Output mappings to KV core
    assign start_o      = kv_regs_q.reg[REG_CTRL][0];
    assign auto_scale_o = kv_regs_q.reg[REG_CTRL][1];
    assign int_en_o     = kv_regs_q.reg[REG_CTRL][2];

    assign length_o     = kv_regs_q.reg[REG_LEN];
    assign src_addr_o   = kv_regs_q.reg[REG_SRC_ADDR];
    assign dst_addr_o   = kv_regs_q.reg[REG_DST_ADDR];
    assign scale_o      = kv_regs_q.reg[REG_SCALE];
    assign zp_o         = kv_regs_q.reg[REG_ZP];

    // STATUS (read-only)
    always_comb begin
        kv_regs_d = kv_regs_q;

        // Read-only STATUS register fields
        kv_regs_d.reg[REG_STATUS][0] = done_i;
        kv_regs_d.reg[REG_STATUS][1] = busy_i;
        kv_regs_d.reg[REG_STATUS][2] = irq_i;
    end

endmodule
