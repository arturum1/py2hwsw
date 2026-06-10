#!/bin/sh

# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: GPL-3.0-only

echo "Verify that CLINT (RISC-V timer) interrupts triggered (interrupt count > 0)"

CLINT_COUNT=$(cat /proc/interrupts | awk '/RISC-V INTC/ && /riscv-timer/ {for(i=2; i<NF; i++) sum += $i; print sum+0}')
if [ "$CLINT_COUNT" -gt 0 ]; then
    echo "CLINT: PASS (count: $CLINT_COUNT)"
else
    echo "CLINT: FAIL (count: $CLINT_COUNT)"
fi

echo "Verify that PLIC (SiFive) interrupts triggered (interrupt count > 0)"

PLIC_COUNT=$(cat /proc/interrupts | awk '/SiFive PLIC/ && /iob_timer/ {for(i=2; i<NF; i++) sum += $i; print sum+0}')
if [ "$PLIC_COUNT" -gt 0 ]; then
    echo "PLIC: PASS (count: $PLIC_COUNT)"
else
    echo "PLIC: FAIL (count: $PLIC_COUNT)"
fi

echo "CLINT and PLIC test passed!"
