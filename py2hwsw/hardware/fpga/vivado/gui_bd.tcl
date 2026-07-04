# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: GPL-3.0-only

# Parse positional args (same order as build.tcl)
set vars {NAME FPGA_TOP CSR_IF BOARD VSRC INCLUDE_DIRS IS_FPGA USE_EXTMEM USE_ETHERNET}
foreach var $vars arg $argv {
    set $var $arg
}

# Create project and Block Design with PS7
source vivado/$BOARD/board.tcl

# Open the BD in the GUI for inspection
open_bd_design [get_files system.bd]
regenerate_bd_layout

puts ""
puts "Block Design is ready for inspection in the GUI."
puts "Close Vivado or type 'exit' in the Tcl Console when done."
puts ""
