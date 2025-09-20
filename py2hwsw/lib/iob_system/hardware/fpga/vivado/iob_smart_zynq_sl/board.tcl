# SPDX-FileCopyrightText: 2025 IObundle
#
# SPDX-License-Identifier: MIT

# Set FPGA part for the project
set PART xc7z020clg484-1
set_property part $PART [current_project]

#
# Generate IPs for use in the design
#

set ip_dir ./ip

# Make sure IP directory exists
if { ![file isdirectory $ip_dir]} {
    file mkdir $ip_dir
}

#
# Xilinx Processing System 7 IP
#

# Create PS7 IP core (Xilinx Processing System 7)
create_ip -name processing_system7 -vendor xilinx.com -library ip -version 5.5 -module_name processing_system7_0 -dir $ip_dir -force

# NOTE: Configure PS7 IP core here
# set clock, reset, and disable M_AXI_GP0
set_property -dict [list \
    CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_EN_RST0_PORT {1} \
    CONFIG.PCW_USE_M_AXI_GP0 {0} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {50.0} \
] [get_ips processing_system7_0]

if { $USE_EXTMEM > 0 } {
    # Enable HP0 AXI slave interface for DDR
    set_property CONFIG.PCW_USE_S_AXI_HP0 {1} [get_ips processing_system7_0]
    # Optionally set data width (default is 32, can be 64 or 128 depending on your design)
    # set_property CONFIG.PCW_S_AXI_HP0_DATA_WIDTH {32} [get_ips processing_system7_0]
    # You can enable other HP ports similarly:
    # set_property CONFIG.PCW_USE_S_AXI_HP1 {1} [get_ips processing_system7_0]
    # etc.
}

# Print the PS7 configuration
report_property [get_ips processing_system7_0]

# Generate the output products for the PS7 IP
generate_target all [get_ips processing_system7_0]

puts "Created and configured PS7 IP at $ip_dir/processing_system7_0"

#
# Ethernet IPs
#

if { $USE_ETHERNET > 0 } {
    # Read verilog wrappers of Xilinx IPs required for Ethernet
    read_verilog vivado/$BOARD/iob_xilinx_ibufg.v
    read_verilog vivado/$BOARD/iob_xilinx_oddre1.v
}
