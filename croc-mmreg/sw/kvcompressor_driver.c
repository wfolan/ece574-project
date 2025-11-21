#include "uart.h"
#include "print.h"
#include "timer.h"
#include "gpio.h"
#include "util.h"

#define FIXED_PI2  0xC90F
#define ANGLE_STEP (FIXED_PI2 / 16)
#define BASE_ADDR  0x20001020

volatile int *cordic = (int *) BASE_ADDR;

int main(void) {
  uart_init();
  uint32_t start, end;
  int angle = 0;
  int sine;
  int i;

  // Start timer and write initial angle
  start = get_mcycle();

  cordic[0] = angle;     // wr_input_angle
  cordic[1] = 0x1;       // wr_control: start = 1

  // Wait for completion
  while ((cordic[2] & 0x1) == 0)
    ; // Wait until done bit set

  // End timer
  end = get_mcycle();

  // Read result 
  sine = cordic[3];
  printf("Cordic HW Cycles: %x\n", end - start);
  printf("HW %x -> %x\n", angle, sine);

  // Sweep angles like the SW test 
  angle = ANGLE_STEP;
  for (i = 0; i < 4; i++) {
    cordic[0] = angle;
    cordic[1] = 0x1;  // start again

    while ((cordic[2] & 0x1) == 0)
      ;

    sine = cordic[3];
    printf("HW %x -> %x\n", angle, sine);

    angle += ANGLE_STEP;
  }

  uart_write_flush();
  return 1;
}
