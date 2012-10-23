#define SYSMEMREMAP (*(unsigned int *)(0x40048000))

void map_normal () {
  SYSMEMREMAP = 2;
}

void map_boot () {
  SYSMEMREMAP = 0;
}

#define U0REG(x) (*(volatile unsigned int *)((x) + 0x40008000))
#define U0THR U0REG(0x00)
#define U0RBR U0REG(0x00)
#define U0DLL U0REG(0x00)
#define U0DLM U0REG(0x04)
#define U0FCR U0REG(0x08)
#define U0LCR U0REG(0x0C)
#define U0LSR U0REG(0x14)
#define U0FDR U0REG(0x28)
#define SYSAHBCLKDIV (*(volatile unsigned int *)(0x40048078))
#define UARTCLKDIV (*(volatile unsigned int *)(0x40048098))

void baud_max () {
  while (!(U0LSR & (1 << 6)));
  SYSAHBCLKDIV = 1;
  UARTCLKDIV = 1;
  U0FDR = (1 << 4) | 0; // disable fractional
  U0LCR |= 1 << 7; // DLAB = 1
  U0DLM = 0;
  U0DLL = 1; // 12e6 / 16 / 1 = 750000
  U0LCR &= ~(1 << 7); // DLAB = 0
  U0FCR = 0x7; // reset fifos*/
}
