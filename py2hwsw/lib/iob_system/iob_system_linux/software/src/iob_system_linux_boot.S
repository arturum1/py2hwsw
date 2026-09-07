# SPDX-FileCopyrightText: 2025 IObundle
#
# SPDX-License-Identifier: MIT

#include "iob_system_linux_conf.h"
#include "iob_system_linux_mmap.h"

// Bootloader stack address: at the end of the bootloader region == at the end of the firmware region
#define STACK_ADDR (IOB_SYSTEM_LINUX_FW_BASEADDR + (1 << IOB_SYSTEM_LINUX_FW_ADDR_W))

// Runtime-configurable jump address and DTB address (set by boot.c).
// Default to legacy values for backward compatibility (no runtime override).
// .data is used (not .bss) because .bss disallows non-zero initial values in
// standard RISC-V assembly; the bootloader runs in place so .data values are
// loaded with the binary at link time.
.section .data
.globl next_boot_addr
next_boot_addr: .word IOB_SYSTEM_LINUX_FW_BASEADDR
.globl next_boot_dtb_addr
next_boot_dtb_addr: .word 0x00F80000

.section .init
.globl main

  //set stack pointer
  lui sp, %hi(STACK_ADDR)
  addi sp, sp, %lo(STACK_ADDR)

  //call main
  jal ra, main

#ifdef IOB_SYSTEM_LINUX_FENCEI
  // Ensure that instruction fetches after jump are synced with previous writes - uses RISC-V 'Zifencei' extension
  fence.i
#endif

  // Set up kernel entry arguments (must be here, not in C code, to avoid
  // clobbering by function calls).
  // For Linux M-mode boot, a0 = Hart ID and a1 = DTB address.
  // Both jump target and DTB address come from runtime-configurable globals
  // populated by boot.c.
  li a0, 0                                // Hart ID (single-core)
  lui a1, %hi(next_boot_dtb_addr)
  addi a1, a1, %lo(next_boot_dtb_addr)
  lw a1, 0(a1)                            // a1 = DTB address
  li a2, 0
  li a3, 0
  li a4, 0
  li a5, 0
  li a6, 0
  li a7, 0

  // Jump to the address stored in next_boot_addr (set at runtime by boot.c)
  lui x5, %hi(next_boot_addr)
  addi x5, x5, %lo(next_boot_addr)
  lw x5, 0(x5)
  jalr x0, 0(x5)
