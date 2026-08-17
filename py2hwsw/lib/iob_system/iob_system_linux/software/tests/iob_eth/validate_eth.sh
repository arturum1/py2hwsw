#!/bin/sh

# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: GPL-3.0-only

# IOb-ETH ethoc Driver Automated Validation Script
#
# This script orchestrates the full validation of the IOb-Eth core
# against the Linux ethoc driver. It runs on the host machine and
# coordinates the SoC-side test and host-side companion script.
#
# Usage:
#   sh validate_eth.sh [options]
#
# Options:
#   -s <soc_ip>      SoC IP address (default: 192.168.1.10)
#   -c <host_ip>     Host IP address (default: auto-detect)
#   -i <interface>   Host Ethernet interface (default: auto-detect)
#   -S <ssh_user>   SSH user for SoC (enables remote execution)
#   -p <password>   SSH password for SoC (requires sshpass on host)
#   --no-ping        Skip the pre/post ping connectivity gate
#   -d <ms>          Stress-RX inter-frame gap in ms (default 2; 0 = back-to-back, informational only on 50 MHz SoC)
#   -b <bytes>       Stress-RX payload size in bytes (default 1468)
#   --downup         After the run, recycle the SoC link (down/up) and
#                    re-test ping to characterize the post-wedge recovery
#   -v               Verbose output
#   -h               Show this help
#
# If -S is provided, the script will:
#   1. Build the test binary
#   2. Copy it to the SoC via scp
#   3. Run the test remotely via ssh
#   4. Run the host companion script locally
#   5. Collect and display results
#
# If -S is not provided, the script assumes:
#   1. The test binary is already on the SoC
#   2. You will run iob_eth_test manually on the SoC
#   3. This script only starts the host companion

SOC_IP="192.168.1.10"
HOST_IP=""
INTERFACE=""
SSH_USER=""
SSH_PASS=""
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=120 -o ServerAliveInterval=15 -o ServerAliveCountMax=10"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
HOST_SCRIPT="$SCRIPT_DIR/iob_eth_host.py"
TEST_BIN="$SCRIPT_DIR/iob_eth_test"
PORT=9000
HOST_PID=""
VERBOSE=""
PING_ENABLED=1
STRESS_DELAY=""
STRESS_SIZE=""
RUN_DOWNUP=0

usage() {
    sed -n '3,/^$/s/^#//p' "$0"
    exit 0
}

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        -s) SOC_IP="$2"; shift 2 ;;
        -c) HOST_IP="$2"; shift 2 ;;
        -i) INTERFACE="$2"; shift 2 ;;
        -S) SSH_USER="$2"; shift 2 ;;
        -p) SSH_PASS="$2"; shift 2 ;;
        -d) STRESS_DELAY="$2"; shift 2 ;;
        -b) STRESS_SIZE="$2"; shift 2 ;;
        --downup) RUN_DOWNUP=1; shift ;;
        -v) VERBOSE="-v"; shift ;;
        --no-ping) PING_ENABLED=0; shift ;;
        -h) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# Setup sshpass prefix if password was provided
STRESS_ARGS=""
if [ -n "$STRESS_DELAY" ]; then
    STRESS_ARGS="$STRESS_ARGS -d $STRESS_DELAY"
fi
if [ -n "$STRESS_SIZE" ]; then
    STRESS_ARGS="$STRESS_ARGS -b $STRESS_SIZE"
fi
SSH_PASS_CMD=""
if [ -n "$SSH_PASS" ]; then
    if command -v sshpass >/dev/null 2>&1; then
        SSH_PASS_CMD="sshpass -p $SSH_PASS"
        echo "Using sshpass for SSH authentication"
    else
        echo "ERROR: sshpass is required when using -p <password> but is not installed."
        echo "       Install it with: sudo apt install sshpass"
        echo "       Or use SSH keys instead of a password."
        exit 1
    fi
fi

# Auto-detect host interface if not specified
if [ -z "$INTERFACE" ]; then
    # Find the non-loopback interface with a default route
    INTERFACE=$(ip route show default | awk '{print $5}' | head -n1)
    if [ -z "$INTERFACE" ]; then
        # Fallback: first non-lo interface
        INTERFACE=$(ls /sys/class/net/ | grep -v lo | head -n1)
    fi
    if [ -z "$INTERFACE" ]; then
        echo "ERROR: Could not auto-detect host interface"
        exit 1
    fi
fi

# Auto-detect host IP if not specified
if [ -z "$HOST_IP" ]; then
    HOST_IP=$(ip -4 addr show dev "$INTERFACE" | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)
    if [ -z "$HOST_IP" ]; then
        echo "ERROR: Could not auto-detect host IP for $INTERFACE"
        exit 1
    fi
fi

echo "=== IOb-ETH ethoc Driver Automated Validation ==="
echo ""
echo "Host interface: $INTERFACE"
echo "Host IP:        $HOST_IP"
echo "SoC IP:         $SOC_IP"
echo ""

# Function to cleanup on exit
cleanup() {
    if [ -n "$HOST_PID" ]; then
        echo ""
        echo "Stopping host companion script (PID=$HOST_PID)..."
        kill "$HOST_PID" 2>/dev/null
        wait "$HOST_PID" 2>/dev/null
    fi
}
trap cleanup EXIT

# Ping sanity check against the SoC.
# Pre-run: informational. Post-run: a hard gate (report, do not fix).
run_ping() {
    [ "$PING_ENABLED" = "1" ] || return 0
    local label="$1"
    local out recv rtt max_rtt=0 ooo=0 count=0
    out=$(ping -n -c 10 -W 1 "$SOC_IP" 2>&1)
    recv=$(printf '%s\n' "$out" | awk '/received/{print $4}')
    [ -z "$recv" ] && recv=0
    # parse per-reply RTT, detect out-of-order icmp_seq
    printf '%s\n' "$out" | awk '
        /bytes from/{
            seq++; cur=$0
            if (match(cur, /icmp_seq=[0-9]+/)) {
                v=substr(cur, RSTART+9, RLENGTH-9)+0
                if (seen) { if (v < prev) ooo++; }
                prev=v; seen=1
            }
            if (match(cur, /time=[0-9.]+/))
                rtt=substr(cur, RSTART+5, RLENGTH-5)+0
            if (rtt > max) max=rtt
        }
        END{ print ooo" "max }
    ' | read ooo max_rtt || { ooo=0; max_rtt=0; }

    echo "  Ping ($label): $recv/10 replies, max RTT ${max_rtt}ms, OOO=$ooo"
    case "$label" in
        before)
            if [ "$recv" = "0" ]; then
                echo "  WARNING: SoC not reachable via ping before test."
                echo "           Validation will likely fail. (use --no-ping to skip)"
            fi
            return 0
            ;;
        after)
            local pass=1
            [ "$recv" != "10" ] && pass=0
            if [ "$max_rtt" != "0" ] && [ "$max_rtt" -ge 500 ]; then pass=0; fi
            [ "$ooo" != "0" ] && pass=0
            if [ "$pass" = "1" ]; then
                echo "  Ping gate (after): PASS"
                return 0
            else
                echo "  Ping gate (after): FAIL (connectivity degraded: $recv/10, maxRTT=${max_rtt}ms, OOO=$ooo)"
                return 1
            fi
            ;;
    esac
    return 0
}

# Step 0: pre-run ping baseline
echo ""
echo "Pre-run ping baseline..."
run_ping before
echo ""

# Step 1: Build if source exists and binary is older
if [ -f "$SCRIPT_DIR/iob_eth_test.c" ] && [ ! -f "$TEST_BIN" ]; then
    echo "Building test binary..."
    make -C "$SCRIPT_DIR" || {
        echo "ERROR: Build failed"
        exit 1
    }
    echo ""
fi

if [ ! -f "$TEST_BIN" ] && [ -z "$SSH_USER" ]; then
    echo "WARNING: Test binary not found at $TEST_BIN"
    echo "         Build with 'make' or run test manually on SoC."
    echo ""
fi

# Step 2: Check ARP entry for SoC on host
echo "Checking ARP entry for SoC..."
SOC_MAC=$(arp -n "$SOC_IP" 2>/dev/null | awk '/ether/{print $3}')
if [ -n "$SOC_MAC" ]; then
    echo "  ARP: $SOC_IP -> $SOC_MAC"
else
    echo "  Note: SoC ARP entry will be learned from first packet"
fi
echo ""

# Step 3: Copy binary and run on SoC (if SSH configured)
if [ -n "$SSH_USER" ]; then
    echo "Copying test binary to SoC..."
    $SSH_PASS_CMD scp $SSH_OPTS "$TEST_BIN" "${SSH_USER}@${SOC_IP}:/tmp/iob_eth_test" || {
        echo "ERROR: SCP failed"
        exit 1
    }

    echo "Making binary executable on SoC..."
    $SSH_PASS_CMD ssh $SSH_OPTS "${SSH_USER}@${SOC_IP}" "chmod +x /tmp/iob_eth_test" || {
        echo "ERROR: chmod failed"
        exit 1
    }
    echo ""
fi

# Step 4: Start host companion script in background
echo "Starting host companion script on $INTERFACE..."
python3 "$HOST_SCRIPT" "$INTERFACE" --soc-ip "$SOC_IP" --port "$PORT" &
HOST_PID=$!
echo "  Host PID: $HOST_PID"

# Give host script time to start
sleep 2

# Verify host script is running
if ! kill -0 "$HOST_PID" 2>/dev/null; then
    echo "ERROR: Host companion script failed to start"
    exit 1
fi
echo "  Host script is running"
echo ""

# Step 5: Run test on SoC
echo "Running test on SoC..."
echo "-------------------------------------------"

if [ -n "$SSH_USER" ]; then
    # Run remotely
    $SSH_PASS_CMD ssh $SSH_OPTS "${SSH_USER}@${SOC_IP}" \
        "/tmp/iob_eth_test -s $SOC_IP -c $HOST_IP -v $STRESS_ARGS" 2>&1
    TEST_EXIT=$?
else
    # Run locally (assume we're on the SoC or have access)
    if [ -x "$TEST_BIN" ]; then
        "$TEST_BIN" -s "$SOC_IP" -c "$HOST_IP" $VERBOSE 2>&1
        TEST_EXIT=$?
    else
        echo "Test binary not found. Please run manually on the SoC:"
        echo "  $TEST_BIN -s $SOC_IP -c $HOST_IP $STRESS_ARGS $VERBOSE"
        echo ""
        echo "Press Enter when the test is complete, or Ctrl+C to abort."
        read -r
        TEST_EXIT=0
    fi
fi

echo "-------------------------------------------"
echo ""

# Step 6: Check kernel error counters
echo "Checking kernel error counters..."

if [ -n "$SSH_USER" ]; then
    $SSH_PASS_CMD ssh $SSH_OPTS "${SSH_USER}@${SOC_IP}" "
        SOC_IF=\$(ls /sys/class/net/ | grep -v lo | head -n1)
        echo '--- /proc/net/dev ---'
        head -2 /proc/net/dev 2>/dev/null || true
        grep \"\$SOC_IF\" /proc/net/dev 2>/dev/null || echo '(interface not found in /proc/net/dev)'

        echo ''
        echo '--- Error counters ---'
        RX_ERRS=\$(grep \"\$SOC_IF\" /proc/net/dev 2>/dev/null | awk '{print \$4}')
        TX_ERRS=\$(grep \"\$SOC_IF\" /proc/net/dev 2>/dev/null | awk '{print \$12}')
        echo \"rx_errors: \$RX_ERRS\"
        echo \"tx_errors: \$TX_ERRS\"
    " 2>&1
else
    echo "--- /proc/net/dev ---"
    head -1 /proc/net/dev 2>/dev/null || true
    grep "$INTERFACE" /proc/net/dev 2>/dev/null || echo "(interface not found in /proc/net/dev)"

    echo ""
    echo "--- Error counters ---"
    RX_ERRS=$(grep "$INTERFACE" /proc/net/dev 2>/dev/null | awk '{print $4}')
    TX_ERRS=$(grep "$INTERFACE" /proc/net/dev 2>/dev/null | awk '{print $12}')
    echo "rx_errors: $RX_ERRS"
    echo "tx_errors: $TX_ERRS"
fi

echo ""

# Step 7: Check interrupts
echo "Checking interrupt activity..."
if [ -n "$SSH_USER" ]; then
    $SSH_PASS_CMD ssh $SSH_OPTS "${SSH_USER}@${SOC_IP}" "
        SOC_IF=\$(ls /sys/class/net/ | grep -v lo | head -n1)
        echo '--- /proc/interrupts (ethoc) ---'
        grep -i \"ethoc\|\$SOC_IF\" /proc/interrupts 2>/dev/null || echo '(no ethoc interrupts found)'
    " 2>&1
else
    echo "--- /proc/interrupts (ethoc) ---"
    grep -i "ethoc\|$INTERFACE" /proc/interrupts 2>/dev/null || echo "(no ethoc interrupts found)"
fi

echo ""

# Step 8: Post-run connectivity / ping gate (report, do not fix)
echo "Post-run ping gate..."
run_ping after
PING_GATE=$?
echo ""

# Step 8b: Optional down/up wedge characterization
run_downup() {
    [ "$RUN_DOWNUP" = "1" ] || return 0
    echo "Characterizing down/up recovery after the run (wedge repro):"
    if [ -n "$SSH_USER" ]; then
        $SSH_PASS_CMD ssh $SSH_OPTS "${SSH_USER}@${SOC_IP}" \
            "iface=\$(ls /sys/class/net/ | grep -v lo | head -n1); \
             ip link set \$iface down; sleep 1; ip link set \$iface up; sleep 2; \
             ip -brief addr show \$iface" 2>&1
    else
        echo "  (no -S given; recycle the SoC link manually)"
    fi
    echo "  Ping $SOC_IP after down/up (per-reply latency):"
    ping -n -c 10 -W 2 "$SOC_IP" 2>&1 | \
        awk '/bytes from/{print "    " ++n":\t"$0}'
    echo "  done."
    return 0
}
run_downup
echo ""

# Step 9: Final verdict
echo "============================================"

if [ $TEST_EXIT -eq 0 ] && [ $PING_GATE -eq 0 ]; then
    echo "OVERALL VALIDATION: PASS"
else
    echo "OVERALL VALIDATION: FAIL"
    if [ $PING_GATE -ne 0 ]; then
        echo "  Cause: post-test connectivity gate failed (ping lost to $SOC_IP)"
    fi
    # A failed ping gate dominates, even if the exit code was 0.
    [ $TEST_EXIT -eq 0 ] && TEST_EXIT=1
fi

exit $TEST_EXIT
