#include "kvcompressor.h"

// -----------------------------------------------------------------------------
// kvcompressor_run_blocking()
// -----------------------------------------------------------------------------
void kvcompressor_run_blocking(uint32_t src_addr,
                               uint32_t dst_addr,
                               uint32_t length,
                               bool     auto_scale,
                               uint32_t scale_q15,
                               uint32_t zp)
{
    // Program core parameters
    kv_write(REG_LEN,        length);
    kv_write(REG_SRC_ADDR,   src_addr);
    kv_write(REG_DST_ADDR,   dst_addr);

    // Manual scale/ZP (ignored in auto-scale mode)
    if (!auto_scale) {
        kv_write(REG_SCALE, scale_q15);
        kv_write(REG_ZP,    zp);
    }

    // Build CTRL word
    uint32_t ctrl = 0;
    if (auto_scale)
        ctrl |= CTRL_AUTO_SCALE;

    // Pulse START
    kv_write(REG_CTRL, ctrl | CTRL_START);
    kv_write(REG_CTRL, ctrl);

    // Wait until hardware finishes
    while (!(kv_read(REG_STATUS) & STATUS_DONE))
        ;
}
