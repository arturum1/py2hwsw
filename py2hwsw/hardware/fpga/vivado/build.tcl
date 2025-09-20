# SPDX-FileCopyrightText: 2025 IObundle
#
# SPDX-License-Identifier: MIT

# Extract CLI positional args
set vars {NAME FPGA_TOP CSR_IF BOARD VSRC INCLUDE_DIRS IS_FPGA USE_EXTMEM USE_ETHERNET}
foreach var $vars arg $argv {
    set $var $arg
    puts "$var = $arg"
}

set proj_dir "./vivado_proj"
set proj_name "${NAME}_prj"

# Create project
create_project $proj_name $proj_dir -force

# Add Verilog and EDIF sources
foreach file [split $VSRC \ ] {
    puts $file
    if {[file extension $file] == ".edif"} {
        add_files -fileset sources_1 $file
    } elseif {$file != "" && $file != " " && $file != "\n"} {
        add_files -fileset sources_1 $file
    }
}

# Set the include directories property on the 'sources_1' fileset
# Vivado expects one string with space-separated directories
set_property include_dirs [join $INCLUDE_DIRS " "] [get_filesets sources_1]

# Read board properties
source vivado/$BOARD/board.tcl

# Pre-map custom assignments
if {[file exists "vivado/premap.tcl"]} {
    source "vivado/premap.tcl"
}

# Add SDC constraints
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

# Set top module
set_property top $FPGA_TOP [current_fileset]

# Out-of-context/FPGA flag handling (optional, for simple project mode we skip OOC)
# You can add support for OOC runs if needed

# Run Synthesis
launch_runs synth_1
wait_on_run synth_1

# Open synthesized design
open_run synth_1

# Apply constraints via .tcl script (allows conditional constraints)
if {[file exists "vivado/$BOARD/$NAME\_dev.tcl"]} {
    source vivado/$BOARD/$NAME\_dev.tcl
}

# Post-map custom assignments
if {[file exists "vivado/postmap.tcl"]} {
    source "vivado/postmap.tcl"
}

# Run Implementation
launch_runs impl_1
wait_on_run impl_1

# Open implemented design
open_run impl_1

# Reports (after implementation)
report_clocks
report_clock_interaction
report_cdc -details
report_bus_skew

report_clocks -file reports/$FPGA_TOP\_$PART\_clocks.rpt
report_clock_interaction -file reports/$FPGA_TOP\_$PART\_clock_interaction.rpt
report_cdc -details -file reports/$FPGA_TOP\_$PART\_cdc.rpt
report_synchronizer_mtbf -file reports/$FPGA_TOP\_$PART\_synchronizer_mtbf.rpt
report_utilization -file reports/$FPGA_TOP\_$PART\_utilization.rpt
report_timing -file reports/$FPGA_TOP\_$PART\_timing.rpt
report_timing_summary -file reports/$FPGA_TOP\_$PART\_timing_summary.rpt
report_timing -file reports/$FPGA_TOP\_$PART\_timing_paths.rpt -max_paths 30
report_bus_skew -file reports/$FPGA_TOP\_$PART\_bus_skew.rpt

if {$IS_FPGA == "1"} {
    write_bitstream -force $FPGA_TOP.bit
    write_hw_platform -fixed -include_bit -force hw_platform.xsa
} else {
    # Non-FPGA flow, optional: export netlist
    write_verilog -force $FPGA_TOP\_netlist.v
    write_verilog -force -mode synth_stub ${FPGA_TOP}_stub.v
}

# FIXME: Apparently this does not work for vivado projects that do not have a block design.
# # Export hardware platform (used to later import in Xilinx vitis for FSBL generation on Zynq boards)
# set_property platform.board_id $BOARD [current_project]
# set_property platform.name $NAME [current_project]
# write_hw_platform -force -file hw_platform.xsa
