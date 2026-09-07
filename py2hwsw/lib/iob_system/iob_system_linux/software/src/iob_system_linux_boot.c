/*
 * SPDX-FileCopyrightText: 2026 IObundle
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#include "clint.h"
#include "iob_bsp.h"
#include "iob_printf.h"
// #include "iob_spi.h"
// #include "iob_spidefs.h"
// #include "iob_spiplatform.h"
#include "iob_system_linux_conf.h"
#include "iob_system_linux_mmap.h"
#include "iob_uart16550.h"
#ifdef IOB_SYSTEM_LINUX_USE_ETHERNET
#include "iob_eth.h"
#endif
#include <stdio.h>
#include <string.h>

#define PROGNAME "IOb-Bootloader"

#define DC1 17 // Device Control 1 (used to indicate end of bootloader)

//
// Newlib syscalls
//
// The bootloader is linked with `-lnosys`, which provides weak stub
// implementations of the POSIX syscalls referenced by newlib's stdio layer
// (e.g. via iob_printf). The `-lnosys` stubs trigger linker warnings
// ("_close is not implemented and will always fail", etc.). Provide our own
// weak stubs here so the linker resolves the references silently and the
// bootloader keeps working even if some stdio path is exercised.
//

#include <reent.h>
#include <sys/stat.h>
#include <unistd.h>

__attribute__((weak)) int _close(int fd) {
  (void)fd;
  return -1;
}

__attribute__((weak)) int _fstat(int fd, struct stat *st) {
  (void)fd;
  (void)st;
  return -1;
}

__attribute__((weak)) int _isatty(int fd) {
  (void)fd;
  return 0;
}

__attribute__((weak)) int _lseek(int fd, int ptr, int dir) {
  (void)fd;
  (void)ptr;
  (void)dir;
  return 0;
}

__attribute__((weak)) int _read(int fd, char *buf, int len) {
  (void)fd;
  (void)buf;
  (void)len;
  return 0;
}

__attribute__((weak)) int _write(int fd, const char *buf, int len) {
  (void)fd;
  (void)buf;
  (void)len;
  return len;
}

#define FLASH_FILE_SIZE_OFFSET 0x0   // sector 0, subsector 0
#define FLASH_FIRMWARE_OFFSET 0x1000 // sector 0, subsector 1

// Ethernet utility functions

// Assumes 64-byte cache lines (common in VexiiRiscv/VexRiscv); adjust if
// different
#define CACHE_LINE_SIZE 64

// Clean and invalidate CPU data cache. Write-back dirty lines to memory and
// then discard cache contents.
void flush_cache(void *start, size_t len) {
#ifdef IOB_SYSTEM_LINUX_CBO
  char *end = (char *)start + len;
  char *ptr;

  // Round start down to line boundary
  ptr = (char *)((uintptr_t)start & ~(CACHE_LINE_SIZE - 1));

  // Flush (clean + invalidate) whole lines covering the range
  while (ptr < end) {
    asm volatile("cbo.flush 0(%0)" ::"r"(ptr) : "memory");
    ptr += CACHE_LINE_SIZE;
  }
#else  // NOT IOB_SYSTEM_LINUX_CBO
  // Delay to ensure all data is written to memory
  for (unsigned int i = 0; i < 10; i++)
    asm volatile("nop");
  // Flush VexRiscv CPU internal cache
  asm volatile(".word 0x500F" ::: "memory");
#endif // IOB_SYSTEM_LINUX_CBO
}

#ifdef IOB_SYSTEM_LINUX_USE_ETHERNET
// Send signal by uart to receive file by ethernet
uint32_t uart_recvfile_ethernet(char *file_name) {
  uart16550_puts(UART_PROGNAME);
  uart16550_puts(": requesting to receive file by ethernet\n");

  // send file receive by ethernet request
  uart16550_putc(0x13);

  // send file name (including end of string)
  uart16550_puts(file_name);
  uart16550_putc(0);

  // receive file size
  uint32_t file_size = uart16550_getc();
  file_size |= ((uint32_t)uart16550_getc()) << 8;
  file_size |= ((uint32_t)uart16550_getc()) << 16;
  file_size |= ((uint32_t)uart16550_getc()) << 24;

  // send ACK before receiving file
  uart16550_putc(ACK);

  return file_size;
}
#endif // IOB_SYSTEM_LINUX_USE_ETHERNET

//
// Memory loading
//

// Runtime-configurable jump address and DTB address used by boot.S.
// Populated from a host-sent text file (e.g. "next_boot_addr") so the
// bootloader no longer bakes the jump target into the FPGA bitstream.
extern uint32_t next_boot_addr;
extern uint32_t next_boot_dtb_addr;

// Parse a hex string (e.g. "00400000\n" or "0x400000\n") into a 32-bit value.
// Returns 0 on success and writes the value to *out. Returns -1 on parse
// error (no hex digits found, buffer too large, or out-of-range value).
static int parse_hex_addr(const char *buf, uint32_t size, uint32_t *out) {
  uint32_t value = 0;
  int i = 0;
  int digits = 0;
  // Skip optional "0x" or "0X" prefix
  if (size >= 2 && buf[0] == '0' && (buf[1] == 'x' || buf[1] == 'X')) {
    i = 2;
  }
  for (; i < (int)size; i++) {
    char c = buf[i];
    int digit;
    if (c >= '0' && c <= '9')
      digit = c - '0';
    else if (c >= 'a' && c <= 'f')
      digit = 10 + c - 'a';
    else if (c >= 'A' && c <= 'F')
      digit = 10 + c - 'A';
    else
      break; // stop on newline or any non-hex char
    value = (value << 4) | (uint32_t)digit;
    digits++;
    if (digits > 8)
      return -1; // would overflow 32 bits
  }
  if (digits == 0)
    return -1;
  *out = value;
  return 0;
}

int compute_mem_load_txt(char file_name_array[4][50],
                         long int file_address_array[4], char *file_start_addr,
                         uint32_t file_size) {
  int state = 0;
  int file_name_count = 0;
  int file_count = 0;
  char hexChar = 0;
  int hexDecimal = 0;
  int i = 0;
  for (i = 0; i < file_size; i++) {
    hexChar = *(file_start_addr + i);
    // uart16550_puts(&hexChar); /* Used for debugging. */
    if (state == 0) {
      if (hexChar == ' ') {
        file_name_array[file_count][file_name_count] = '\0';
        file_name_count = 0;
        file_address_array[file_count] = 0;
        file_count = file_count + 1;
        state = 1;
      } else {
        file_name_array[file_count][file_name_count] = hexChar;
        file_name_count = file_name_count + 1;
      }
    } else if (state == 1) {
      if (hexChar == '\n') {
        state = 0;
      } else {
        if ('0' <= hexChar && hexChar <= '9') {
          hexDecimal = hexChar - '0';
        } else if ('a' <= hexChar && hexChar <= 'f') {
          hexDecimal = 10 + hexChar - 'a';
        } else if ('A' <= hexChar && hexChar <= 'F') {
          hexDecimal = 10 + hexChar - 'A';
        } else {
          uart16550_puts(PROGNAME);
          uart16550_puts(": invalid hexadecimal character.\n");
        }
        file_address_array[file_count - 1] =
            file_address_array[file_count - 1] * 16 + hexDecimal;
      }
    }
  }

  return file_count;
}

void console_get_files(int file_count, long int file_address_array[4],
                       char *file_start_addr, char file_name_array[4][50],
                       int file_sizes[4]) {
  int i = 0;
  char *file_addr = NULL;
  for (i = 0; i < file_count; i++) {
    file_addr = (char *)(file_start_addr + file_address_array[i]);
#ifdef IOB_SYSTEM_LINUX_USE_ETHERNET
    // Receive data from console via Ethernet
    file_sizes[i] = uart_recvfile_ethernet(file_name_array[i]);
    eth_rcv_file(file_addr, file_sizes[i]);
#else  // NOT IOB_SYSTEM_LINUX_USE_ETHERNET
    // Receive data from console via UART
    file_sizes[i] = uart16550_recvfile(file_name_array[i], file_addr);
#endif // IOB_SYSTEM_LINUX_USE_ETHERNET
  }
}

//
// Flash memory
//

// void program_flash(int file_count, long int file_address_array[4],
//                    char *file_start_addr, int file_sizes[4]) {
//   int i = 0;
//   unsigned int flash_addr = 0x0;
//   char *prog_data = NULL;
//   int next_subsector = 0;
//
//   // erase SPI Flash
//   flash_addr = FLASH_FILE_SIZE_OFFSET;
//   spiflash_erase_address_range(flash_addr, 4 * file_count);
//
//   // store file sizes
//   prog_data = (char *)file_sizes;
//   spiflash_memProgram(prog_data, 4 * file_count, flash_addr);
//
//   for (i = 0; i < file_count; i++) {
//     flash_addr = FLASH_FIRMWARE_OFFSET + (next_subsector * SUBSECTOR_SIZE);
//     prog_data = file_start_addr + file_address_array[i];
//     spiflash_erase_address_range(flash_addr, file_sizes[i]);
//     printf("Program %d: addr: %p\tflash: %x\tsize: %d\n", i, prog_data,
//            flash_addr, file_sizes[i]);
//     spiflash_memProgram(prog_data, file_sizes[i], flash_addr);
//     printf("Program %d: complete\n", i);
//     next_subsector += (((file_sizes[i] + SUBSECTOR_SIZE - 1) /
//     SUBSECTOR_SIZE));
//   }
// }
//
// void read_flash(int file_count, long int file_address_array[4],
//                 char *file_start_addr) {
//   int i = 0;
//   int sample = 0;
//   unsigned int *read_array = NULL;
//   unsigned int spi_data = 0;
//   unsigned int flash_file_start = 0;
//   int read_cnt = 0, read_total = 0;
//   int file_sizes[4] = {0};
//   int next_subsector = 0;
//
//   // get file sizes
//   for (sample = 0; sample < 4 * file_count; sample = sample + 4) {
//     file_sizes[sample >> 2] = spiflash_readmem(FLASH_FILE_SIZE_OFFSET +
//     sample);
//   }
//
//   for (i = 0; i < file_count; i++) {
//     read_array = (unsigned int *)(file_start_addr + file_address_array[i]);
//     flash_file_start =
//         FLASH_FIRMWARE_OFFSET + (next_subsector * SUBSECTOR_SIZE);
//     read_total = file_sizes[i] / 4;
//     read_cnt = 0;
//
//     printf("Read %d: flash: %x\tmem: %p\tsize: %d\n", i, flash_file_start,
//            read_array, file_sizes[i]);
//     for (sample = 0; sample < file_sizes[i]; sample = sample + 4) {
//       read_array[sample >> 2] = spiflash_readmem(flash_file_start + sample);
//       // progress every 10%
//       if (read_cnt % (read_total / 10) == 0) {
//         printf("\tRead %d: %d%%\n", i, read_cnt * 100 / read_total);
//       }
//       read_cnt++;
//     }
//     next_subsector += (((file_sizes[i] + SUBSECTOR_SIZE - 1) /
//     SUBSECTOR_SIZE));
//   }
// }

#ifdef IOB_SYSTEM_LINUX_TRAP_HANDLER
//
// Trap handler
//

// Simple hex conversion for 32-bit integer into a buffer (without stdlib)
void uint32_to_hex_str(uint32_t value, char *buffer) {
  const char hex_chars[] = "0123456789ABCDEF";
  for (int i = 0; i < 8; i++) {
    buffer[7 - i] = hex_chars[value & 0xF];
    value >>= 4;
  }
  buffer[8] = '\0';
}

void trap_handler(void) {
  uint32_t mcause, mepc;

  asm volatile("csrr %0, mcause" : "=r"(mcause));
  asm volatile("csrr %0, mepc" : "=r"(mepc));

  // Buffers for printing
  char buffer[20];

  uart16550_puts("Trap occurred!\nMCause: 0x");
  uint32_to_hex_str(mcause, buffer);
  uart16550_puts(buffer);
  uart16550_puts("\nMEPC: 0x");
  uint32_to_hex_str(mepc, buffer);
  uart16550_puts(buffer);
  uart16550_puts("\n");

  asm volatile("ebreak"); // halt for debugger, optional
}

void set_trap_vector(void (*handler)(void)) {
  uintptr_t addr = (uintptr_t)handler;
  asm volatile("csrw mtvec, %0" : : "r"(addr));
}
#endif

//
// Main
//

int main() {
  int run_linux = 0;
  int file_size;
  char *prog_start_addr;

  // init uart
  uart16550_init(UART0_BASE, IOB_BSP_FREQ / (16 * IOB_BSP_BAUD));

  // connect with console
  do {
    if (uart16550_txready())
      uart16550_putc((char)ENQ);
  } while (!uart16550_rxready());

#ifdef IOB_SYSTEM_LINUX_TRAP_HANDLER
  set_trap_vector(trap_handler);
#endif

  // welcome message
  uart16550_puts(PROGNAME);
  uart16550_puts(": connected!\n");

#ifdef IOB_SYSTEM_LINUX_USE_EXTMEM
  uart16550_puts(PROGNAME);
  uart16550_puts(": DDR in use and program runs from DDR\n");
#endif

  // address to copy firmware to
  prog_start_addr = (char *)(IOB_SYSTEM_LINUX_FW_BASEADDR);

  while (uart16550_getc() != ACK) {
    uart16550_puts(PROGNAME);
    uart16550_puts(": Waiting for Console ACK.\n");
  }

#ifndef IOB_SYSTEM_LINUX_INIT_MEM
  printf_init(&uart16550_putc);

#ifdef IOB_SYSTEM_LINUX_USE_ETHERNET
  // Init ethernet
  eth_init(ETH0_BASE, IOB_BSP_FREQ, &flush_cache, &printf_);
  // Wait for PHY reset to finish
  eth_wait_phy_rst();
#endif // IOB_SYSTEM_LINUX_USE_ETHERNET

  char boot_flow[20] = {0};

  file_size = uart16550_recvfile("boot.flow", boot_flow);
  if (file_size > 20) {
    printf("Error: boot.flow file size is too large\n");
    return -1;
  }

  file_size =
      uart16550_recvfile("../iob_system_linux_mem.config", prog_start_addr);

  // compute_mem_load_txt
  char file_name_array[4][50];
  long int file_address_array[4];
  int file_sizes[4] = {0};
  int file_count = compute_mem_load_txt(file_name_array, file_address_array,
                                        prog_start_addr, file_size);

  if (!strcmp(boot_flow, "CONSOLE_TO_FLASH")) {
    uart16550_puts(PROGNAME);
    uart16550_puts(": CONSOLE_TO_FLASH\n");
    // // init spi flash controller
    // spiflash_init(SPI0_BASE);
    // // Read files from console
    // console_get_files(file_count, file_address_array, prog_start_addr,
    //                   file_name_array, file_sizes);
    // program_flash(file_count, file_address_array, prog_start_addr,
    // file_sizes);
  } else if (!strcmp(boot_flow, "FLASH_TO_EXTMEM")) {
    uart16550_puts(PROGNAME);
    uart16550_puts(": FLASH_TO_EXTMEM\n");
    // // init spi flash controller
    // spiflash_init(SPI0_BASE);
    // read_flash(file_count, file_address_array, prog_start_addr);
  } else {
    uart16550_puts(PROGNAME);
    uart16550_puts(": CONSOLE_TO_EXTMEM\n");
    // Read files from console to external memory
    console_get_files(file_count, file_address_array, prog_start_addr,
                      file_name_array, file_sizes);
  }

  // Check if running Linux
  for (int i = 0; i < file_count; i++) {
    if (!strcmp(file_name_array[i], "rootfs.cpio.gz")) {
#ifdef SIMULATION
      // Running Linux: setup required dependencies
      uart16550_sendfile("test.log", 12, "Test passed!");
      // Disable console exclusive message identifiers (avoids conflicts with
      // chars sent by Linux boot process)
      uart16550_putc((char)DC1);
#endif
      run_linux = 1;
      break;
    }
  }
#else // INIT_MEM = 1
#ifdef IOB_SYSTEM_LINUX_RUN_LINUX
  // Running Linux: setup required dependencies
  uart16550_sendfile("test.log", 12, "Test passed!");
  // Disable console exclusive message identifiers (avoids conflicts with
  // chars sent by Linux boot process)
  uart16550_putc((char)DC1);
#endif
#endif // INIT_MEM

  // Receive runtime-configurable next-boot address and DTB address from the
  // host. These are sent as small ASCII text files containing a hex value
  // (e.g. "00400000\n"). If the host does not provide them, the defaults set
  // in boot.S (next_boot_addr = IOB_SYSTEM_LINUX_FW_BASEADDR,
  // next_boot_dtb_addr = 0x00F80000) are used. This runs in both INIT_MEM=0
  // (console-loaded firmware) and INIT_MEM=1 (firmware baked into bitstream)
  // cases so the jump target is always correct.
  {
    char addr_buf[32];
    uint32_t parsed;
    int n;

    n = uart16550_recvfile("iob_system_linux_next_boot_addr", addr_buf);
    if (n > 0 && n < (int)sizeof(addr_buf)) {
      if (parse_hex_addr(addr_buf, (uint32_t)n, &parsed) == 0) {
        next_boot_addr = parsed;
        uart16550_puts(PROGNAME);
        uart16550_puts(": next_boot_addr = 0x");
        for (int j = 7; j >= 0; j--) {
          int nib = (next_boot_addr >> (j * 4)) & 0xF;
          uart16550_putc(nib < 10 ? '0' + nib : 'a' + nib - 10);
        }
        uart16550_puts("\n");
      } else {
        uart16550_puts(PROGNAME);
        uart16550_puts(": invalid next_boot_addr payload, using default\n");
      }
    }

    n = uart16550_recvfile("iob_system_linux_next_boot_dtb_addr", addr_buf);
    if (n > 0 && n < (int)sizeof(addr_buf)) {
      if (parse_hex_addr(addr_buf, (uint32_t)n, &parsed) == 0) {
        next_boot_dtb_addr = parsed;
      }
    }
  }

  // run firmware
  uart16550_puts(PROGNAME);
  uart16550_puts(": Restart CPU to run user program...\n");
  uart16550_txwait();

#ifndef SIMULATION
  // Terminate console if running Linux on FPGA
  // We may want to use a different terminal emulator for Linux (like minicom)
  if (run_linux)
    uart16550_finish();
#endif
}
