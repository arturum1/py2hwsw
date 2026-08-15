/*
 * SPDX-FileCopyrightText: 2026 IObundle
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#include "iob_printf.h"
#include "iob_timer.h"
#include "iob_uart.h"
#include "mmap.h"

#define FREQ 100000000
#define BAUD 3000000

int main() {
  unsigned long long elapsed;
  unsigned int elapsedu;

  // init timer and uart
  timer_init(TIMER0_BASE);
  uart_init(UART_BASE, FREQ / BAUD);

  printf("\nHello world!\n");

  // set timer interrupt threshold for 10ms
  timer_set_interrupt(FREQ / 100);
  printf("\nTimer interrupt set for 10ms (@%dHz)\n", FREQ / 100);

  // read current timer count, compute elapsed time
  elapsed = timer_get_count();
  elapsedu = elapsed / (FREQ / 1000000);

  printf("\nExecution time: %d clock cycles\n", (unsigned int)elapsed);
  printf("\nExecution time: %dus @%dMHz\n\n", elapsedu, FREQ / 1000000);

  uart_finish();
}
