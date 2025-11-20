// kvcomp_hw_pkg.sv
package kvcompressorhw_pkg;

  // Base address is assigned in user_pkg.sv (e.g., 0x20001020 or similar)
  localparam int KVCOMP_NUM_WORDS = 7;

  // Word offsets (word-aligned: addr = BASE + 4*index)
  typedef enum int unsigned {
    KVCOMP_CTRL_IDX     = 0,  // CTRL
    KVCOMP_LEN_IDX      = 1,  // LEN
    KVCOMP_SCALE_IDX    = 2,  // SCALE
    KVCOMP_ZP_IDX       = 3,  // ZP
    KVCOMP_IN_DATA_IDX  = 4,  // IN_DATA (INT16 sample)
    KVCOMP_OUT_DATA_IDX = 5,  // OUT_DATA (INT8 result)
    KVCOMP_STATUS_IDX   = 6   // STATUS
  } kvcomp_reg_index_e;

  // CTRL register bits
  typedef struct packed {
    logic        start;        // [0]   start vector (SW writes 1, HW clears)
    logic        mode_k_ch;    // [1]   0 = V_per_token, 1 = K_per_channel (placeholder)
    logic        clamp_en;     // [2]   clamp to unsigned [0,255]
    logic        int_en;       // [3]   interrupt enable (future use)
    logic [27:0] rsvd;         // [31:4]
  } kvcomp_ctrl_t;

  // STATUS register bits
  typedef struct packed {
    logic        busy;         // [0] compressor running
    logic        done;         // [1] last vector finished (sticky until SW clears)
    logic        err;          // [2] error flag (unused in v1, but reserved)
    logic        out_valid;    // [3] OUT_DATA holds a fresh sample
    logic [27:0] rsvd;         // [31:4]
  } kvcomp_status_t;

  typedef struct packed {
    logic [31:0] ctrl;         // kvcomp_ctrl_t view via cast
    logic [31:0] len;          // number of samples in vector
    logic [31:0] scale;        // SCALE in Q8.8 fixed point (lower 16 bits used)
    logic [31:0] zp;           // ZP in lower 8 bits (signed or unsigned per mode)
    logic [31:0] in_data;      // input INT16 sample (lower 16 bits)
    logic [31:0] out_data;     // output INT8 sample (lower 8 bits)
    logic [31:0] status;       // kvcomp_status_t view via cast
  } kvcomp_regs_t;

endpackage
