volatile int *mmreg = (int *) 0x20001000;

int main() {

  mmreg[0] = 0xA0001A00;
  mmreg[1] = 0xA1002A00;
 
  return 1;
}
