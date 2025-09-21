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

puts "\n\n#########################################################"
puts "Creating minimal block design project to generate ZYNQ Processing System 7"
puts "#########################################################\n\n"

# Create new project in subdirectory
create_project -force zynq_minimal_proj ./zynq_minimal_proj -part $PART
set_property target_language Verilog [current_project]

# Create the block design
create_bd_design zynq_design

# Add ZYNQ7 Processing System IP
# Product Guide: https://docs.amd.com/v/u/en-US/pg082-processing-system7
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0

# Run block automation to configure PS7 for board, clocks, IOs, AXI etc
#apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_bclk_clks true} $ps7_inst

# Optional: You can set some PS7 configuration properties here if needed
# set_property CONFIG.C_USE_AXI_HP0 1 [get_bd_cells processing_system7_0]

# NOTE: Configure PS7 IP core here
# - Disable M_AXI_GP0 (General purpose manager AXI bus)
# - Enable FCLK0 (system clock)
# - Configure FCLK0 frequency
# - Enable FCLK_RESET0_N (system reset)
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {0} \
] [get_bd_cells processing_system7_0]

if { $USE_EXTMEM > 0 } {
    # Enable HP0 AXI slave interface for DDR (runs at FCLK0 frequency)
    set_property CONFIG.PCW_USE_S_AXI_HP0 {1} [get_bd_cells processing_system7_0]
    # Optionally set data width (default is 32, can be 64 or 128 depending on your design)
    # set_property CONFIG.PCW_S_AXI_HP0_DATA_WIDTH {32} [get_ips processing_system7_0]
    # You can enable other HP ports similarly:
    # set_property CONFIG.PCW_USE_S_AXI_HP1 {1} [get_ips processing_system7_0]
    # etc.
}

# Print PS7 IP configuration
report_property [get_bd_cells processing_system7_0]

# Validate design
validate_bd_design

# Generate output products (necessary for synthesis)
generate_target all [get_bd_designs zynq_design.bd]

# Save the design
save_bd_design

# Create HDL wrapper for BD and set as top
make_wrapper -files [get_files zynq_design.bd] -top

# Add the wrapper HDL file explicitly to the project
add_files -norecurse ./zynq_minimal_proj/zynq_minimal_proj.gen/sources_1/bd/zynq_design/hdl/zynq_design_wrapper.v

# Set top module to wrapper
set_property top zynq_design_wrapper [current_fileset]

# Launch synthesis and wait
launch_runs synth_1 -verbose
wait_on_run synth_1

# Launch implementation and wait
launch_runs impl_1 -to_step write_bitstream -verbose
wait_on_run impl_1

# Export hardware platform with bitstream embedded (XSA for Vitis/FSBL)
write_hw_platform -fixed -include_bit -force ./hw_platform.xsa

# Close zynq_minimal_proj
close_project

puts "\n\n#########################################################"
puts "Created and configured PS7 IP (block design) at zynq_minimal_proj/zynq_minimal_proj.gen/sources_1/bd/zynq_design/ip/zynq_design_processing_system7_0_0/synth/zynq_design_processing_system7_0_0.v"
puts "#########################################################\n\n"
# It would be nice if we could just do this instead of creating an entire vivado project with block design.
# But since we need the .xsa file for Vitis, I don't think it is possible.
# create_ip -vlnv xilinx.com:ip:processing_system7:5.5 -module_name processing_system7_0

# Copy file and include PS7 IP in the project
import_ip zynq_minimal_proj/zynq_minimal_proj.srcs/sources_1/bd/zynq_design/ip/zynq_design_processing_system7_0_0/zynq_design_processing_system7_0_0.xci
# Print PS7 IP configuration
report_property [get_ips zynq_design_processing_system7_0_0]

#
# Ethernet IPs
#

if { $USE_ETHERNET > 0 } {
    # Read verilog wrappers of Xilinx IPs required for Ethernet
    read_verilog vivado/$BOARD/iob_xilinx_ibufg.v
    read_verilog vivado/$BOARD/iob_xilinx_oddre1.v
}
