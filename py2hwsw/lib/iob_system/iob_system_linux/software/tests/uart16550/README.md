# IOb-UART16550 Linux Driver Compatibility Test

This test suite validates the **IOb-UART16550** hardware core's compatibility with the standard Linux `8250/16550` serial driver. It uses a loopback configuration between two UART instances to verify register-level behavior, timing, and data integrity across various operation modes.

## Prerequisites

- Two UART16550 instances integrated into the SoC.
- RS232 interfaces (TX/RX and optionally RTS/CTS) connected in a loopback fashion.
- Linux `8250` driver loaded, with devices available at `/dev/ttyS1` and `/dev/ttyS2` (default).

## Building

The test program is cross-compiled for RISC-V (rv32imac) using the provided `nix-shell` environment. By default, it uses dynamic linking to minimize binary size (~20KB).

```bash
nix-shell path/to/iob_linux --run 'make'
```

If your SoC lacks a full C library, you can build a standalone static binary (~800KB) instead:

```bash
nix-shell path/to/iob_linux --run 'make STATIC=1'
```

## Usage

### Automated Validation (Recommended)
Transfer both the binary and the shell script to the SoC and run:

```bash
sh validate_uart.sh
```

This script executes the full test matrix and automatically cross-references the results with kernel-level error counters and interrupt statistics.

### Manual Execution
To run only the user-space test suite:

```bash
./iob_uart16550_test [/dev/ttyS_TX] [/dev/ttyS_RX]
```

## Test Coverage

1.  **Configuration Matrix**: Iterates through multiple baud rates (9600–115200), data bits (7, 8), stop bits (1, 2), and parities (None, Even, Odd). This validates the Line Control Register (LCR) and clock divider implementation.
2.  **Stress Test**: Performs a 4KB data transfer at 115200 baud to exercise hardware FIFOs (FCR) and interrupt handling (IER/IIR).
3.  **Flow Control**: Verifies hardware RTS/CTS handshaking via the Modem Control (MCR) and Modem Status (MSR) registers.

## Automated Validation Logic

The `validate_uart.sh` script performs the following checks:
- **Loopback Integrity**: Ensures data sent on one port is correctly received on the other across all configurations.
- **Kernel Error Counters**: Inspects `/proc/tty/driver/serial` for framing (`fe`), parity (`pe`), or overrun (`oe`) errors. Any non-zero value indicates a hardware/timing mismatch.
- **Interrupt Verification**: Checks `/proc/interrupts` to ensure the UART is triggering interrupts. If IRQ counts do not increase, the driver may be incorrectly falling back to polling mode.
- **FIFO Detection**: Ideally, the kernel should report the device as a `16550A` in `dmesg`, confirming successful FIFO probing.
