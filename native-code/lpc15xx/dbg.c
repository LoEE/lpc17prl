#define SYSMEMREMAP (*(unsigned int *)(0x40074000))

void map_normal () {
  SYSMEMREMAP = 2;
}

void map_boot () {
  SYSMEMREMAP = 0;
}

#define U0REG(x) (*(volatile unsigned int *)((x) + 0x40040000))
#define U0CFG  U0REG(0x00)
#define U0STAT U0REG(0x08)
#define U0BRG  U0REG(0x20)
#define SYSAHBCLKDIV (*(volatile unsigned int *)(0x400740C0))
#define UARTCLKDIV (*(volatile unsigned int *)(0x400740D0))
#define FRGCTRL (*(volatile unsigned int *)(0x40074128))

void baud_max () {
  while (!(U0STAT & (1 << 3))); // TXIDLE
  SYSAHBCLKDIV = 1;
  UARTCLKDIV = 1;
  U0CFG = 0;
  FRGCTRL = 0xff; // disable fractional
  U0BRG = 1-1; // 12e6 / 16 / 1 = 750000
  U0CFG = (1 << 2) | (1 << 0); // 8N1
}
