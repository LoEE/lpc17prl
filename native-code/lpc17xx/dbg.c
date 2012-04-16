#define MEMMAP (*(unsigned int *)(0x400fc040))

void map_normal () {
  MEMMAP = 1;
}

void map_boot () {
  MEMMAP = 0;
}

#define U0REG(x) (*(volatile unsigned int *)((x) + 0x4000C000))
#define U0THR U0REG(0x00)
#define U0RBR U0REG(0x00)
#define U0DLL U0REG(0x00)
#define U0DLM U0REG(0x04)
#define U0FCR U0REG(0x08)
#define U0LCR U0REG(0x0C)
#define U0LSR U0REG(0x14)
#define U0FDR U0REG(0x28)
#define PCLKSEL0 (*(volatile unsigned int *)(0x400FC1A8))

void baud_max () {
  while (!(U0LSR & (1 << 6)));
  PCLKSEL0 |= 1 << 6;
  U0FDR = (13 << 4) | 3;
  U0LCR |= 1 << 7; // DLAB = 1
  U0DLM = 0;
  U0DLL = 3;
  U0LCR &= ~(1 << 7); // DLAB = 0
  U0FCR = 0x7; // reset fifos
}
