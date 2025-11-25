#ifndef KVCOMPRESSOR_H
#define KVCOMPRESSOR_H

#include <stdint.h>
#include <stdbool.h>

// MMIO Base Address (same as what cordic was)
#define KV_BASE_ADDR   0x20001020
#define KV             ((volatile uint32_t *) KV_BASE_ADDR)

// Register Offsets
#define REG_CTRL        0
#define REG_LEN         1
#define REG_SRC_ADDR    2
#define REG_DST_ADDR    3
#define REG_SCALE       4
#define REG_ZP          5
#define REG_STATUS      6

// CTRL Register Fields
#define CTRL_START       (1 << 0)
#define CTRL_AUTO_SCALE  (1 << 1)
#define CTRL_INT_EN      (1 << 2)

// STATUS Register Fields
#define STATUS_DONE      (1 << 0)
#define STATUS_BUSY      (1 << 1)
#define STATUS_IRQ       (1 << 2)

// Inline MMIO Helpers
static inline void kv_write(uint32_t reg, uint32_t value) {
    KV[reg] = value;
}

static inline uint32_t kv_read(uint32_t reg) {
    return KV[reg];
}

#endif // KVCOMPRESSOR_H
