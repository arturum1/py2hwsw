# SPDX-FileCopyrightText: 2025 IObundle
#
# SPDX-License-Identifier: MIT

# Set FPGA part for the project
set PART xc7z020clg484-1

puts "\n\n #### Calling vivado in subshell to create PS7 BD design ####\n\n"
# Call vivado in a subshell (will run in interactive mode without affecting this one)
exec vivado -nojournal -log reports/vivado_ps7.log -mode batch -source vivado/$BOARD/ps7_ip.tcl -tclargs $USE_EXTMEM >@stdout 2>@stderr
puts "\n\n #### Vivado subshell finished creating PS7 BD design ####\n\n"

# Set correct FPGA
set_property part $PART [current_project]

# It would be nice if we could just do this instead of creating an entire vivado project with block design.
# But since we need the .xsa file for Vitis, I don't think it is possible.
# FIXME: DEBUG The PS7 IP was already created in BD design above. This is duplicate but just for testing.
create_ip -vlnv xilinx.com:ip:processing_system7:5.5 -module_name zynq_design_processing_system7_0_0
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {0} \
] [get_ips zynq_design_processing_system7_0_0]
generate_target all [get_files ./ip/zynq_design_processing_system7_0_0/zynq_design_processing_system7_0_0.xci]
synth_ip [get_files ./ip/zynq_design_processing_system7_0_0/zynq_design_processing_system7_0_0.xci]

# Copy file and include PS7 IP in the project
#import_ip zynq_minimal_proj/zynq_minimal_proj.srcs/sources_1/bd/zynq_design/ip/zynq_design_processing_system7_0_0/zynq_design_processing_system7_0_0.xci
# Print PS7 IP configuration
report_property [get_ips zynq_design_processing_system7_0_0]

# Read constraints for PS7 fixed ports
read_xdc vivado/$BOARD/ps7_io.sdc

#
# Ethernet IPs
#

if { $USE_ETHERNET > 0 } {
    # Read verilog wrappers of Xilinx IPs required for Ethernet
    read_verilog vivado/$BOARD/iob_xilinx_ibufg.v
    read_verilog vivado/$BOARD/iob_xilinx_oddre1.v
}
