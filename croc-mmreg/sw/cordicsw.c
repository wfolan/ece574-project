#include "uart.h"
#include "print.h"
#include "timer.h"
#include "gpio.h"
#include "util.h"

// SW CORDIC

#define FIXED_AG_CONST  0x4dba
#define PI2 0xc90f

typedef int             fixed; /* <int,FRAC> fixed-point */

static const fixed Angles[]={
  0x6487,
  0x3b58,
  0x1f5b,
  0xfea,
  0x7fd,
  0x3ff,
  0x1ff,
  0xff,
  0x7f,
  0x3f,
  0x1f,
  0xf,
  0x7,
  0x3,
  0x1
};

fixed quadrant(fixed inangle) {
  unsigned q = 0;

  if (inangle > 4*PI2)
    inangle = inangle - 4*PI2;

  if (inangle > 3*PI2)
    return 3;
  else if (inangle > 2*PI2)
    return 2;
  else if (inangle > PI2)
    return 1;

  return 0;
}

fixed angleadj(fixed inangle) {
  if (inangle > 4*PI2)
    inangle = inangle - 4*PI2;

  if (inangle > 3*PI2)
    return (4*PI2 - inangle);
  else if (inangle > 2*PI2)
    return (inangle - 2*PI2);
  else if (inangle > PI2)
    return (2*PI2 - inangle);

  return inangle;
}

fixed accumulator(fixed inangle, fixed inangleadd) {
  inangle = inangle + inangleadd;

  if (inangle > 4*PI2)
    inangle = inangle - 4*PI2;

  return inangle;
}

fixed cordicsine(fixed inangle) {
  fixed X, Y, TargetAngle, CurrAngle;
  unsigned Step;

  X=FIXED_AG_CONST;   /* AG_CONST * cos(0) */
  Y=0;                /* AG_CONST * sin(0) */

  TargetAngle = angleadj(inangle);
  CurrAngle=0;
  for(Step=0; Step < (15+1); Step++) {
    fixed NewX;
    if (TargetAngle > CurrAngle) {
      NewX       =  X - (Y >> Step);
      Y          = (X >> Step) + Y;
      X          = NewX;
      CurrAngle += Angles[Step];
    } else {
      NewX       = X + (Y >> Step);
      Y          = -(X >> Step) + Y;
      X          = NewX;
      CurrAngle -= Angles[Step];
    }
  }

  if (quadrant(inangle) < 2)
    return  Y;
  else
    return -Y;
}

int main(void) {
  fixed angle, angleadd;
  volatile fixed sinetmp;
  fixed sine;
  unsigned i;
  uint32_t start, end;

  uart_init();

  angleadd = PI2/16;

  start = get_mcycle();
  sinetmp = cordicsine(0);
  end   = get_mcycle();
  printf("Cordic SW Cycles: %x\n", end - start);

  angle = angleadd;
  for (i=0; i<4; i++) {
    sine = cordicsine(angle);
    printf("SW %x -> %x\n", angle, sine);
    angle = accumulator(angle, angleadd);
  }
  uart_write_flush();

  return 1;
}
