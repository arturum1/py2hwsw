<!--
SPDX-FileCopyrightText: 2026 IObundle

SPDX-License-Identifier: GPL-3.0-only
-->

# IOb-ETH ethoc Driver Compatibility Test

This test suite validates the **IOb-Eth** hardware core's compatibility with the standard Linux `ethoc` (OpenCores Ethernet MAC) network driver. It exercises the main driver operation modes through the standard Linux networking API (sockets, ioctl, ethtool, sysfs, /proc).

## Architecture

```
SoC (RISC-V Linux)                     Host (x86 Linux)
┌────────────────────────┐  100Mbps  ┌────────────────────────┐
│ iob_eth_test (C)       │◄─────────►│ iob_eth_host.py (Py3)  │
│ UDP sockets (port 9000)│  eth0↔X  │ echo/reply to commands  │
│ ioctl / ethtool / sysfs│           │                         │
└────────────────────────┘           └────────────────────────┘
```

The SoC-side test program sends command packets to the host companion script and validates the responses, statistics, and driver state at each step.

## Prerequisites

- IOb-Eth core integrated into the SoC, connected at 100Mbps to a Linux host
- Linux `ethoc` driver loaded (`compatible = "opencores,ethoc"` in device tree)
- Network interface available on both SoC and host
- Python 3 on the host (no external dependencies)
- `riscv64-unknown-linux-gnu-gcc` cross-compiler (in `nix-shell`)

## Building

The test program is cross-compiled for RISC-V (rv32imac) using the provided `nix-shell` environment. By default, it uses dynamic linking to minimize binary size.

```bash
nix-shell path/to/iob_linux --run 'make'
```

If your SoC lacks a full C library, build a standalone static binary:

```bash
nix-shell path/to/iob_linux --run 'make STATIC=1'
```

## Running

### Automated Validation (Recommended)

The `validate_eth.sh` script runs the entire test suite end-to-end:

```bash
# On the host, with SSH access to the SoC:
sh validate_eth.sh -S root -s 192.168.1.10 -i enp0s3

# Without SSH (run test manually on SoC):
sh validate_eth.sh -s 192.168.1.10 -i enp0s3

# Skip the pre/post host ping gate (e.g. ICMP blocked on the SoC):
sh validate_eth.sh ... --no-ping
```

### Manual Execution

**On the host machine:**
```bash
python3 iob_eth_host.py <interface> --soc-ip <soc_ip>
# Example: python3 iob_eth_host.py enp0s3 --soc-ip 192.168.1.10
```

**On the SoC (in a separate terminal):**
```bash
./iob_eth_test -s <soc_ip> -c <host_ip> [-v]
# Example: ./iob_eth_test -s 192.168.1.10 -c 192.168.1.1 -v
```

## Command-Line Options

### iob_eth_test

| Option | Description |
|--------|-------------|
| `-i <iface>` | Network interface (auto-detected if omitted) |
| `-s <soc_ip>` | SoC IP address |
| `-c <host_ip>` | Host IP address (**required**) |
| `-d <ms>` | Stress-RX inter-frame gap in ms (default 2; 0 = back-to-back, informational only on 50 MHz SoC) |
| `-b <bytes>` | Stress-RX payload size in bytes (default 1468) |
| `-v` | Verbose output (register dumps, detailed stats) |
| `-h` | Show help |

### iob_eth_host.py

| Option | Description |
|--------|-------------|
| `<interface>` | Host Ethernet interface (**required**) |
| `--soc-ip <ip>` | SoC IP address (for static ARP entry) |
| `--port <port>` | UDP port (default: 9000) |
| `-h` | Show help |

## Test Coverage

The test suite validates the primary ethoc driver operation modes:

### 1. Interface Detection & Driver Binding
Scans `/sys/class/net/` to find the interface whose driver resolves to `ethoc`.

### 2. Interface Bring-Up
Sets `IFF_UP` via `SIOCSIFFLAGS` and verifies the flag sticks via `SIOCGIFFLAGS`.

### 3. MAC Address Read/Write
Validates `ethoc_get_mac_address()`, `ethoc_set_mac_address()`, `MAC_ADDR0/1` register read/write via `ioctl(SIOCGIFHWADDR)` / `ioctl(SIOCSIFHWADDR)`.

### 4. Default Register State
Dumps all 21 MAC registers via ethtool. Verifies MODER = `CRC|PAD|FULLD|RXEN|TXEN`, IPGT = `0x15`, INT_MASK = `0x7F`, TX_BD_NUM valid.

### 5. Link State Detection
Reads link state via sysfs and ethtool (always passes — informational only).

### 6. MII/MDIO PHY Access
Reads PHY registers 0–4 via `SIOCGMIIPHY`/`SIOCGMIIREG`. Values are displayed but not validated against expected bit patterns.

### 7. Basic TX Frame Transmission
Sends a UDP frame, checks `tx_packets` increased and `tx_errors` did not.

### 8. TX Frame Size Range
Tests frames at 60, 128, 512, and 1468 bytes. Checks `tx_packets` increased and `tx_errors` did not for each size.

### 9. Basic RX Frame Reception
Sends a UDP echo request, receives the echo response, validates payload length and content, checks `rx_packets` increased and `rx_errors` did not.

### 10. RX Frame Size Range
Tests reception of various frame sizes with payload integrity verification.

### 11. Broadcast Reception
Checks `IFF_BROADCAST` flag, sends a broadcast frame, validates host acknowledges receipt.

### 12. Promiscuous Mode
Sets `IFF_PROMISC` via `SIOCSIFFLAGS` and verifies the flag is reflected back.

### 13. Loopback Mode
Sets `IFF_LOOPBACK` and verifies via ethtool register dump that `MODER_LOOP` (bit 7) is set by `ethoc_set_multicast_list()`, and cleared when the flag is removed. Note: IOb-Eth hardware has no loopback data path (dest MAC is not compared), so no self-RX is asserted — reported as a known gap.

### 14. MTU Change Rejection
Verifies MTU change is rejected (accepts `EINVAL`/`EOPNOTSUPP`/`ENODEV`/`ENOSYS`) and MTU remains at 1500.

### 15. ethtool Ring Parameters
Validates `ethoc_get_ringparam()`: TX power-of-two, total BDs ≤ 128, no mini/jumbo pending. *(Fixes bug where command `0x0a` read link status instead of ring params.)*

### 16. ethtool Set Ring Parameters
Validates `ethoc_set_ringparam()`: rejects `tx_pending=0`, `tx+rx > num_bd`, and nonzero mini/jumbo; performs a live reinit to 32/32, checks the `TX_BD_NUM` register and ring getback, verifies an echo round-trip survives the reinit, then restores the original ring and rechecks connectivity.

### 17. ethtool Driver Info
Validates `ETHTOOL_GDRVINFO`: asserts `driver == "ethoc"` (populated by the kernel from the platform driver) and `regdump_len == 0x54` (ETH_END).

### 18. ethtool Link Settings (speed/duplex)
Reads `ETHTOOL_GLINKSETTINGS` (legacy `ETHTOOL_GSET` fallback) and asserts `speed == 100 Mbps` and `duplex == FULL` when the link is up (skipped with INFO when the link is down).

### 19. Multicast Hash
Sets `IFF_ALLMULTI` and asserts the `ETH_HASH0/1` registers go to `0xffffffff`; joins IPv4 multicast group `239.1.2.3` via `IP_ADD_MEMBERSHIP` and asserts the derived CRC hash bit is set in `ETH_HASH0/1`; drops the group and asserts the bit is cleared. *(Register-level only — IOb-Eth has no RX filtering.)*

### 20. ethtool Register Dump
Validates `ethoc_get_regs()`, `ethoc_get_regs_len()` — full register map at offset 0x00–0x50. *(Fixes bug where command `0x05` (GWOL) silently took the `EOPNOTSUPP` path.)*

### 21. Interrupt Verification
Reads IRQ count from `/proc/interrupts` before and after traffic; verifies count increased.

### 22. Error Counter Clean Check
Verifies that error counters (rx_errors, rx_frame_errors, tx_errors, tx_fifo_errors, tx_carrier_errors) did not increase during traffic. tx_collisions increase is informational only.

### 23. Stress TX Burst
Sends 200 × 1468-byte frames and checks `tx_packets ≥ 200` with no errors and no new ethoc error lines in `dmesg`.

### 24. Stress RX Burst
Requests 200 × 1468-byte frames from the host with a default 2 ms inter-frame gap (sustainable by this 50 MHz SoC); verifies all 200 are received with no `rx_errors` increase and no new `dmesg` `RX: overrun/wrong CRC` lines. With `-d 0` the frames are sent back-to-back at line rate (~8.3 kfps); this exceeds what the SoC can sustain and is reported as `INFO` (not a failure) — see [Known Limitations](#known-limitations).

### 25. Stress Bidirectional
200 interleaved TX/RX echo cycles (1024-byte payloads); asserts a lossless full-duplex round trip (`received == sent`) with no errors and no new `dmesg` errors.

### 26. Interface Down/Up Integrity
Clears `IFF_UP` (drives `ethoc_stop`), then re-sets it (drives `ethoc_open`); verifies the flag, that `MODER_RXEN|TXEN`, `INT_MASK=0x7F`, and `TX_BD_NUM` are restored, and that a clean echo round-trip and IRQ activity survive the open/stop cycle.

### 27. Final Statistics & Connectivity Gate
Dumps key statistics, register values, and ring parameters; then runs a final echo round-trip (connectivity gate) and scans the whole run's `dmesg` for any ethoc RX/TX error lines. If the run used `-d 0` (line-rate burst), residual `dmesg` CRC lines are expected and reported as `INFO` instead of failing.

## Protocol

SoC and host exchange UDP packets on port 9000 with a simple command protocol:

```
[cmd(1)] [id(1)] [len(2)] [payload(0-1468)]
```

| Command | ID | Description |
|---------|-----|-------------|
| ECHO | 0x01 | Host echoes payload back |
| BROADCAST | 0x02 | Host acknowledges broadcast frame |
| STRESS_TX | 0x03 | SoC sends burst; host acknowledges |
| STRESS_RX | 0x04 | Host sends burst of frames (payload: count(2)+size(2)+delay_ms(2)) |
| GET_HOST_MAC | 0x05 | Host returns its MAC address |
| DONE | 0x06 | Test complete signal |

For `STRESS_RX`, the payload is `count(2) + size(2) + delay_ms(2)`. `delay_ms` is the inter-frame gap in milliseconds (backward compatible: a 4-byte payload defaults to 10 ms). Using `delay_ms=0` sends the burst back-to-back to stress the RX path and reproduce the scp "Bad CRC" overflow symptom.

## ethoc Driver Functions Exercised

| Driver Function | What Is Actually Validated | Test(s) |
|----------------|---------------------------|---------|
| `ethoc_open` | IFF_UP flag via SIOCGIFFLAGS; MODER/INT_MASK/ring restored after re-open | 2, 4, 16, 26 |
| `ethoc_stop` | IFF_UP cleared via SIOCGIFFLAGS | 26 |
| `ethoc_reset` | MODER, IPGT, INT_MASK, TX_BD_NUM register defaults via ethtool dump | 4, 26 |
| `ethoc_init_ring` | TX_BD_NUM range, ring parameter counts, live ring reinit | 4, 15, 16, 26 |
| `ethoc_set_mac_address` | MAC read/write via SIOCGIFHWADDR/SIOCSIFHWADDR | 3 |
| `ethoc_set_multicast_list` | MODER_LOOP via IFF_LOOPBACK; ETH_HASH0/1 for IFF_ALLMULTI and MC join/drop | 13, 19 |
| `ethoc_start_xmit` | tx_packets counter increments, tx_errors unchanged | 7, 8, 23, 25 |
| `ethoc_rx` | rx_packets counter increments, payload integrity (echo), dmesg clean | 9, 10, 24 |
| `ethoc_interrupt` | IRQ count in /proc/interrupts increases with traffic | 21 |
| `ethoc_mdio_read/write` | PHY register reads via SIOCGMIIPHY/SIOCGMIIREG (no value assertions) | 6 |
| `ethoc_mdio_poll` | Link state read from sysfs/ethtool (always passes) | 5 |
| `ethoc_change_mtu` | Rejects MTU change (accepts EINVAL/EOPNOTSUPP/ENODEV/ENOSYS) | 14 |
| `ethoc_get_regs` | Register count ≥ 21, full dump at offset 0x00-0x50 | 4, 20 |
| `ethoc_get_regs_len` | regdump_len==0x54 via ETHTOOL_GDRVINFO | 17 |
| `ethoc_get_ringparam` | tx_pending power-of-2, total ≤ 128, no mini/jumbo pending | 15 |
| `ethoc_set_ringparam` | invalid rejection + live reinit round-trip + TX_BD_NUM write-back | 16 |
| `phy_ethtool_get_link_ksettings` | speed==100 Mbps, duplex==full (link up) | 18 |

## Limitations and Future Improvements

The test suite validates the main ethoc driver operation modes (TX, RX, interface lifecycle, MAC configuration, promiscuous/broadcast/loopback modes, and basic ethtool ops). The following areas are **not** covered and would strengthen the validation:

### Driver Entry Points Not Exercised
- `ndo_tx_timeout` (TX hang recovery)
- `ndo_vlan_rx_add_vid` / `ndo_vlan_rx_kill_vid`
- ethtool `set_link_ksettings` (write path), `nway_reset`, `set_wol`
- ethtool `get_strings` / `get_ethtool_stats` / `get_sset_count`

### Registers Never Directly Validated
INT_SOURCE, IPGR1, IPGR2, PACKETLEN, COLLCONF, CTRLMODER, MIIMODER, MIICOMMAND, MIIADDRESS, MIITX_DATA, MIIRX_DATA, MIISTATUS, ETH_TXCTRL are never read or checked for expected values (they are printed by the register dump, test 20, but not asserted). `ETH_HASH0/1` *are* now asserted (test 19), and `MODER_LOOP` is asserted (test 13).

### PHY / MII Gaps
- No `SIOCSMIIREG` calls — PHY register writes are never tested
- Register values are displayed but never validated against expected values (BMCR bits, PHY ID, etc.)
- MII controller registers (MIIMODER, MIIADDRESS, MIICOMMAND, etc.) are never read directly

### Descriptor Rings Never Inspected
TX/RX buffer descriptor content, pointers, and status bits are not examined — only aggregate packet counters are checked.

### Interrupt Coverage
Only proves that IRQs fired (count increased). Does not verify which interrupt cause (TX vs RX vs error) or that NAPI was scheduled.

## Known Limitations

### 50 MHz SoC Cannot Sustain 100 Mbps Line-Rate RX

The RX path is fully hardware (MII → FIFO → descriptor transfer), but the software `ethoc` driver must recycle RX descriptors and copy each frame's payload from the BD RAM to an skb (~1468 B memcpy). At 50 MHz this caps sustained RX at roughly ~1.5 kfps, while a back-to-back 100 Mbps burst delivers ~8.3 kfps. When the RX descriptor ring runs out, the DT stalls, the RX FIFO (2048 B) overflows, and bytes are dropped mid-frame → `RX: wrong CRC` errors and lost frames.

This is an inherent throughput ceiling, **not** a driver/hardware bug. For this reason:

- The **default** Stress RX run uses a 2 ms inter-frame gap (~470 fps), which the SoC sustains losslessly; all gates are strict.
- With `-d 0`, the back-to-back burst is a **worst-case informational probe**: frame loss and CRC errors are reported as `INFO` (expected baseline on this SoC ≈ 14/200 received, ~21 CRC), and the per-test and final `dmesg` gates are relaxed to informational. The counts are always printed so a regression (much worse than baseline) remains visible to a human.
- Packet loss / CRC / physical-layer issues beyond this baseline still cause the strengthened stress tests and final connectivity gate to **fail loudly** (report, don't fix). Use `--no-ping` only to skip the host ping gate.
- ARP cache warm-up workaround required before tests
- UDP-only on a single port; no TCP, ICMP, or raw socket testing

## Suggested Additions
1. PHY register write-back verification (`SIOCSMIIREG`), including a write/read cycle
2. Descriptor ring inspection via debugfs or a small kernel module
3. ethtool stats, strings, and `get_sset_count`
4. TX timeout recovery injection test
5. Register-level write-read-verify for all 21 MAC registers
6. `set_link_ksettings` (advertised-mode change) test
7. True concurrent bidirectional traffic (threads or async I/O)
8. Soak test (long-duration traffic)
