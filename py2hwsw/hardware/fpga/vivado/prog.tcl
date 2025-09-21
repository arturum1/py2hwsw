# SPDX-FileCopyrightText: 2025 IObundle
#
# SPDX-License-Identifier: MIT

# Extract CLI args
set vars {BITSTREAM DEVICE_ID HW_TARGET}
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
    # If DEVICE_ID (index in JTAG chain) is not defined, set it to zero by default
    set DEVICE_ID 0
}

if {![info exists HW_TARGET]} {
    # If HW_TARGET is not defined, use Digilent cable as the default
    set HW_TARGET */xilinx_tcf/Digilent/*
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

# # Print all available hardware targets
# set hw_targets [get_hw_targets]
# puts "Hardware targets:"
# foreach t $hw_targets { puts $t }

# Open the target device on the hardware server
current_hw_target [get_hw_targets $HW_TARGET]
if { [catch {open_hw_target} result] } {
    puts "ERROR: Can't open hardware target.\n"
    exit result
}

# # Print all available hardware devices
# set hw_devices [get_hw_devices]
# puts "Hardware devices:"
# foreach d $hw_devices { puts $d }

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
