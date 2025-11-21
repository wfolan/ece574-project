#include "uart.h"
#include "print.h"
#include "timer.h"
#include "gpio.h"
#include "util.h"

#define KV_BASE_ADDR  0x20001020 //Added KV_
volatile int *kv = (int *) KV_BASE_ADDR; //Ensure this connection works cordic > kv

//EDIT THESE BASED ON WHAT ACTUALLY NEEDS TO BE DONE
#define REG_CTRL       0   // start, mode, clamp, int_en
#define REG_LEN        1   // number of INT16 elements
#define REG_SRC_ADDR   2   // byte address
#define REG_DST_ADDR   3   // byte address
#define REG_SCALE      4   // optional: preset scale
#define REG_ZP         5   // optional: preset zero-point
#define REG_STATUS     6   // busy, done, err

int main(void) {
  uart_init();
  uint32_t start, end;

  // Start timer -- should this go below ?
  start = get_mcycle();

  //configurate initials
  kv[REG_LEN]         = ; 
  kv[REG_SRC_ADDR]    = ;
  kv[REG_DST_ADDR]    = ;

  //add optionals?

  //put start here?
  kv[REG_CTRL]        = 0x1; //controls start (CTRL.start?)

  // Wait for completion
  while ((kv[REG_STATUS] & 0x1) == 0)
    ; // Wait until done

  // End timer
  end = get_mcycle();

  // Read result 
  //output like sine = cordic[3];???
  printf("Cordic HW Cycles: %x\n", end - start);
  printf("HW %x -> %x\n", angle, sine);

  uart_write_flush();
  return 1;
}
