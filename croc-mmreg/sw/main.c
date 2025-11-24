#include <stdint.h>
#include <stdio.h>
#include "kvcompressor.h"

// External cycle counter from Croc runtime
extern uint32_t get_mcycle(void);

// Example buffers (aligned in .data/.bss automatically)
int16_t input_vec[512];
int8_t  output_vec[512];

int main(void) {
    // -------------------------------------------------------------
    // Fill test vector
    // -------------------------------------------------------------
    for (int i = 0; i < 512; i++)
        input_vec[i] = (i - 256) * 2;

    uint32_t src = (uint32_t) input_vec;
    uint32_t dst = (uint32_t) output_vec;

    // -------------------------------------------------------------
    // Run accelerator
    // -------------------------------------------------------------
    uint32_t start_cycle = get_mcycle();

    kvcompressor_run_blocking(src, dst, 512,
                              true,    // auto-scale
                              0,       // scale ignored in auto mode
                              0);      // zp ignored in auto mode

    uint32_t end_cycle = get_mcycle();

    // -------------------------------------------------------------
    // Print performance + output data
    // -------------------------------------------------------------
    printf("KV compressor cycles: %u\n", end_cycle - start_cycle);

    printf("First 16 output bytes:\n");
    for (int i = 0; i < 16; i++)
        printf("%d ", output_vec[i]);
    printf("\n");

    while (1) ;  // halt
}
