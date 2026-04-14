#!/bin/sh

# IOb-UART16550 Automated Validation Script
# This script runs the user-space test and verifies kernel-level counters.

UART1="/dev/ttyS1"
UART2="/dev/ttyS2"

echo "=== IOb-UART16550 Automated Validation ==="

# 1. Run the user-space test suite
echo "Running Loopback Test Matrix..."
./iob_uart16550_test $UART1 $UART2
TEST_RESULT=$?

if [ $TEST_RESULT -ne 0 ]; then
    echo "ERROR: User-space loopback test failed!"
else
    echo "SUCCESS: User-space loopback test passed."
fi

# 2. Check Kernel Error Counters
echo ""
echo "Checking Kernel Driver Statistics (/proc/tty/driver/serial):"
# Extract info for the two UARTs
STATS=$(cat /proc/tty/driver/serial | grep -E "1:|2:")
echo "$STATS"

# Check for framing (fe), parity (pe), or overrun (oe) errors
ERRORS=$(echo "$STATS" | grep -v "fe:0" | grep -v "pe:0" | grep -v "oe:0")

if [ -n "$ERRORS" ]; then
    echo "WARNING: Kernel reported hardware errors (FE/PE/OE)!"
    TEST_RESULT=1
else
    echo "SUCCESS: No hardware-level errors reported by kernel."
fi

# 3. Check Interrupts
echo ""
echo "Checking Interrupt Activity (/proc/interrupts):"
IRQ_INFO=$(grep ttyS /proc/interrupts)
if [ -z "$IRQ_INFO" ]; then
    echo "WARNING: No UART interrupts found in /proc/interrupts. Driver might be in polling mode."
else
    echo "$IRQ_INFO"
fi

# Final Verdict
echo ""
if [ $TEST_RESULT -eq 0 ]; then
    echo "OVERALL VALIDATION: PASS"
    exit 0
else
    echo "OVERALL VALIDATION: FAIL"
    exit 1
fi
