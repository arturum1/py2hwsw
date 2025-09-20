# SPDX-FileCopyrightText: 2025 IObundle
#
# SPDX-License-Identifier: MIT

# Extract CLI args
set vars {BITSTREAM FSBL DEVICE_ID}
foreach var $vars arg $argv {
   set trimmed_arg [string trim $arg]
   if {$trimmed_arg != ""} {
        set $var $trimmed_arg
        puts "$var = $trimmed_arg"
    } else {
        puts "$var is empty"
    }
}

if {![info exists DEVICE_ID]} {
    # If DEVICE_ID is not defined, set it to zero
    set DEVICE_ID 0
}

#place holder for future remote execution
set HOST localhost

# Connect to the Digilent Cable on localhost:3121

# Open Vivado hardware manager
if { [catch {open_hw_manager} result] } {
    puts "ERROR: Can't connect to hardware manager.\n"
    exit result
}

# Connect to hardware server
if { [catch {connect_hw_server -url $HOST:3121} result] } {
    puts "ERROR: Can't connect to hardware server.\n"
    exit result
}

# Open the target device on the hardware server
current_hw_target [get_hw_targets */xilinx_tcf/Digilent/*]
if { [catch {open_hw_target} result] } {
    puts "ERROR: Can't open hardware target.\n"
    exit result
}

set HW_DEVICE [lindex [get_hw_devices] $DEVICE_ID]

# Select the FPGA device
if { [catch {current_hw_device $HW_DEVICE} result] } {
    puts "ERROR: Can't identify hardware device.\n"
    exit result
}
refresh_hw_device -update_hw_probes false $HW_DEVICE

# Program the bitstream to PL
if { [catch {set_property PROGRAM.FILE "./$BITSTREAM" $HW_DEVICE} result] } {
    puts "ERROR: Can't associate bitstream to FPGA.\n"
    exit result
}
if { [catch {program_hw_devices $HW_DEVICE} result] } {
    puts "ERROR: Can't program FPGA.\n"
    exit result
}
# Refresh the hardware device to update the hardware probes
if { [catch {refresh_hw_device $HW_DEVICE} result] } {
    puts "ERROR: Can't refresh hardware device.\n"
    exit result
}

# If FSBL ELF is provided, download and run it on PS7
if { [info exists FSBL] } {
    # Find the processor for PS7 (Zynq typically has one ARM core: ps7_cortexa9_0)
    set PROCESSORS [get_hw_procs]
    set FOUND_PS7 0
    foreach proc $PROCESSORS {
        if {[regexp {ps7_cortexa9_0} $proc]} {
            set FOUND_PS7 1
            set PS7_PROC $proc
            break
        }
    }
    if {$FOUND_PS7} {
        # Download and run the ELF
        if { [catch {dow $FSBL} result] } {
            puts "ERROR: Can't download ELF to PS7.\n"
            exit result
        }
        if { [catch {run} result] } {
            puts "ERROR: Can't run ELF on PS7.\n"
            exit result
        }
        puts "FSBL ELF loaded and started on PS7."
    } else {
        puts "ERROR: PS7 processor not found. ELF not loaded."
    }
}

# Close hardware target and server
if { [catch {close_hw_target} result] } {
    puts "ERROR: Can't close hardware target.\n"
    exit result
}
if { [catch {disconnect_hw_server} result] } {
    puts "ERROR: Can't disconnect hardware server.\n"
    exit result
}
if { [catch {close_hw_manager} result] } {
    puts "ERROR: Can't close hardware manager.\n"
    exit result
}
