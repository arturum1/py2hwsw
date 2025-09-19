# SPDX-FileCopyrightText: 2025 IObundle
#
# SPDX-License-Identifier: MIT

# Vivado TCL Script for IObundle Zynq System IP Packaging and Top-level Project Creation
#
# This script automates the following:
#   - Creation of an IP packaging project for the IObundle system wrapper and packaging it as a Vivado IP (for instantiation in block design)
#   - Creation of a top-level Vivado project to instantiate and synthesize the packaged IP
#
# Reason for creating a new IP project:
#   Packaging the system as a Vivado IP allows for modular integration and reuse in block designs,
#   making it easier to instantiate, configure, and connect the custom logic alongside standard Xilinx IPs
#   (such as PS7) in Zynq-based designs.

# Set FPGA part for the project
set PART xc7z020clg484-1
set_property part $PART [current_project]

# =========== Create a new Vivado project for IP packaging ===========

set ip_dir ./ip

# Ensure the IP directory exists
if { ![file isdirectory $ip_dir]} {
    file mkdir $ip_dir
}

# Create the IP packaging project inside the IP directory
create_project -force ip_packaging_project $ip_dir -part $PART
set_property target_language Verilog [current_project]

# Add sources (Verilog RTL)
# VSRC contains the list of source files, passed from build.tcl
foreach file $VSRC {
    add_files -fileset sources_1 $file
    # Check if source file exists
    if {[file exists $file]} {
        puts "Added source file: $file"
    } else {
        puts "Warning: Source file $file does not exist!"
    }
}


set_property ip_repo_paths $ip_dir [current_project]
# Update IP catalog to include the new IP
update_ip_catalog -rebuild

# List all discovered IPs
puts "[IP packaging project] Found IPs:"
foreach ip [get_ipdefs *] {
    puts $ip
}
puts "Repo paths: [get_property ip_repo_paths [current_project]]"

# Package the project as a Vivado IP
ipx::package_project -root_dir $ip_dir/$NAME -import_files -force

# Set IP metadata properties
set core [ipx::current_core]
# Set required metadata
set_property vendor iobundle.com $core
set_property library user $core
set_property name $NAME $core
set_property version 1.0 $core

set_property taxonomy {{/UserIP}} $core
set_property supported_families {zynq Production} $core

set_property display_name "IOB System" $core
set_property description "IObundle system wrapper" $core

# Save packaged IP and check integrity
ipx::save_core
ipx::check_integrity $core
#ipx::unload_core iobundle.com:user:$NAME:1.0
close_project -delete
puts "IP $NAME packaged at $ip_dir/$NAME"



# ======= Create new top-level project and instantiate the previously packaged IObundle IP ===========
#
# Delete any existing project files
file delete -force .Xil

# Create the top-level Vivado project in ./top_project directory
create_project -force top_project ./top_project -part $PART
set_property target_language Verilog [current_project]

# Add IP repo path to the new project and update catalog
set_property ip_repo_paths $ip_dir [current_project]
update_ip_catalog -rebuild 

# List all discovered IPs
puts "[Top-level project] Found IPs:"
foreach ip [get_ipdefs *] {
    puts $ip
}
puts "Repo paths: [get_property ip_repo_paths [current_project]]"

# Create block design
create_bd_design "design_1"

# Instantiate Zynq Processing System (PS7) IP
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0

# NOTE: Configure PS7 here.
# enable FCLK0, reset0; disable M_AXI_GP0; set FCLK0 frequency
set_property -dict [list \
    CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_EN_RST0_PORT {1} \
    CONFIG.PCW_USE_M_AXI_GP0 {0} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {50.0}\
] [get_bd_cells processing_system7_0]


# Instantiate the previously packaged IObundle system IP
create_bd_cell -type ip -vlnv iobundle.com:user:$NAME:1.0 $NAME\_0

# Instantiate a constant logic '1' cell for control signals
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 constant_1


# Connect PS7 clock and reset outputs to the IObundle IP inputs
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins $NAME\_0/clk_i]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] [get_bd_pins $NAME\_0/arst_i]

# Connect control signals (cke_i and cts_i) to constant '1'
connect_bd_net [get_bd_pins $NAME\_0/cke_i] [get_bd_pins constant_1/dout]
connect_bd_net [get_bd_pins $NAME\_0/rs232_cts_i] [get_bd_pins constant_1/dout]

# AXI interface is not connected here since it's disabled (M_AXI_GP0 = 0)

# NOTE: Add here other connections between PS7, Board IO, and your IP.

# Make UART pins external (will be constrained in the $NAME_dev.sdc file)
make_bd_pins_external -name rs232_txd_o [get_bd_pins $NAME\_0/rs232_txd_o]
make_bd_pins_external -name rs232_rxd_i [get_bd_pins $NAME\_0/rs232_rxd_i]

# Optionally make LED pins external
#make_bd_pins_external [get_bd_pins $NAME\_0/led0]
#make_bd_pins_external [get_bd_pins $NAME\_0/led3]

# Add board and timing constraints (similar implementation as in build.tcl)
if {[file exists "vivado/$BOARD/$NAME\_dev.sdc"]} {
    add_files -fileset constrs_1 vivado/$BOARD/$NAME\_dev.sdc
}
if {[file exists "../src/$NAME.sdc"]} {
    add_files -fileset constrs_1 ../src/$NAME.sdc
}
if {[file exists "../../src/$NAME\_$CSR_IF.sdc"]} {
    add_files -fileset constrs_1 ../src/$NAME\_$CSR_IF.sdc
}
if {[file exists "vivado/$NAME\_tool.sdc"]} {
    add_files -fileset constrs_1 vivado/$NAME\_tool.sdc
}


# Validate block design
validate_bd_design

# Generate output products for block design (HDL, constraints, etc.)
generate_target all [get_bd_designs design_1.bd]

# Save the design
save_bd_design


# Set include directories for synthesis (sources, common sources, etc.)
set_property include_dirs "../src ../common_src ./src ./vivado/$BOARD" [get_filesets sources_1]

# Create HDL wrapper for block design (needed for synthesis)
make_wrapper -files [get_files design_1.bd] -top

# Add the wrapper to your project
add_files -norecurse ./top_project/top_project.gen/sources_1/bd/design_1/hdl/design_1_wrapper.v

# Set the top module for synthesis
set_property top design_1_wrapper [current_fileset]

# Launch synthesis, implementation, and bitstream generation (adjust as needed)

puts "Synthesizing for FPGA"

launch_runs synth_1 -verbose
wait_on_run synth_1

launch_runs impl_1 -to_step write_bitstream -verbose
wait_on_run impl_1

# Export hardware platform including the bitstream (for SDK / Vitis usage)
write_hw_platform -fixed -include_bit -force ./$NAME.xsa

#rename the bitstream to match the project name
#set bitstream_file [get_files -of_objects [get_runs impl_1] -filter {FILE_TYPE == "Bit"}]
#set_property FILE_NAME "$NAME.bit" $bitstream_file

# Terminate script (don't run remaining build.tcl commands)
exit 0
