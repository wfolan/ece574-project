#include "kvcompressor.h"

void kvcompressor_run_blocking(uint32_t src_addr, //address of INT16 input
                               uint32_t dst_addr, //address of INT8 output
                               uint32_t length, //number of INT16 elements
                               bool     auto_scale, //does hw calc its own scale?
                               uint32_t scale_q15, //if no to above, manually provided fixed-pt scale 
                               uint32_t zp) //manual zero point
{
    //kv_write from .h file
    //Assigns REG_ s in kvcompressor_mmreg.sv
    //i.e. first line replaces whats at kv[REG_LEN] with the length
    kv_write(REG_LEN,        length);
    kv_write(REG_SRC_ADDR,   src_addr);
    kv_write(REG_DST_ADDR,   dst_addr);

    // OPTIONAL??? Manual scale/ZP (ignored in auto-scale mode)
    if (!auto_scale) {
        kv_write(REG_SCALE, scale_q15);
        kv_write(REG_ZP,    zp);
    }

    // Build CTRL word
    uint32_t ctrl = 0;
    if (auto_scale)
        ctrl = ctrl | CTRL_AUTO_SCALE; //ctrl bit is only 1 if auto scale is on

    // Pulse START
    kv_write(REG_CTRL, ctrl | CTRL_START);
    kv_write(REG_CTRL, ctrl);

    // Wait until hardware finishes
    while (!(kv_read(REG_STATUS) & STATUS_DONE))
        ;
}
