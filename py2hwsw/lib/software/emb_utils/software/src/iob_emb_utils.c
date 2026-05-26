/*
 * SPDX-FileCopyrightText: 2026 IObundle
 *
 * SPDX-License-Identifier: MIT
 */

void perror(char *s) {
  printf("ERROR: %s", s);
  uart_finish();
}
