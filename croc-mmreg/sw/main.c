#include <stdint.h>
#include <stdbool.h>

#include "lib/inc/uart.h"
#include "lib/inc/timer.h"
#include "lib/inc/print.h"
#include "kvcompressor.h"

// Example buffers
static int16_t input_vec[512]; //input buffer
static int8_t  output_vec[512]; //output buffer

int main(void) {
    uart_init();
    print_str("KV Compressor Demo\n");

    // Loop through and fill every element of the input vector
    for (int i = 0; i < 512; i++)
        input_vec[i] = (i - 256) * 2;

    uint32_t src = (uint32_t) input_vec; //addrss of input vector
    uint32_t dst = (uint32_t) output_vec; //address of output vector

    // Run
    uint32_t start = get_mcycle();

    kvcompressor_run_blocking(src, dst, 512,
                              true,    // auto-scale on
                              0,       // scale ignored
                              0);      // zp ignored

    uint32_t end = get_mcycle();

    // Print performance + output data
    print_str("Cycles: ");
    print_dec(end - start);
    print_str("\n");

    print_str("First 16 output bytes:\n");
    for (int i = 0; i < 16; i++) {
        print_hex(output_vec[i] & 0xFF);  // show signed 8-bit
        print_str(" ");
    }
    print_str("\n");

    while (1) {;}

    return 0;
}
