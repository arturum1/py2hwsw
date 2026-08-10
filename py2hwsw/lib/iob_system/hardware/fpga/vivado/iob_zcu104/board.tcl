# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: GPL-3.0-only

set PART xczu7ev-ffvc1156-2-e

if { $USE_EXTMEM > 0 } {

# Create a temporary project for Zynq (required for BD)
if { [current_project -quiet] == "" } {
    create_project -force -part $PART iob_zcu104 ./iob_zcu104
} else {
    set_property part $PART [current_project]
}
# The board preset needs the board, not just the part
set_property board_part xilinx.com:zcu104:part0:1.1 [current_project]

if { [get_files system.bd] == "" } {
    create_bd_design "system"
    create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e zynq_ultra_ps_e_0

    # The board preset sets the DDR controller for the soldered 2 GB DDR4
    apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
        -config {apply_board_preset "1"} [get_bd_cells zynq_ultra_ps_e_0]

    set_property -dict [list \
        CONFIG.PSU__USE__M_AXI_GP0 {0} \
        CONFIG.PSU__USE__M_AXI_GP1 {0} \
        CONFIG.PSU__USE__M_AXI_GP2 {0} \
        CONFIG.PSU__USE__S_AXI_GP2 {1} \
        CONFIG.PSU__SAXIGP2__DATA_WIDTH {32} \
        CONFIG.PSU__FPGA_PL0_ENABLE {1} \
    ] [get_bd_cells zynq_ultra_ps_e_0]

    make_bd_intf_pins_external [get_bd_intf_pins zynq_ultra_ps_e_0/S_AXI_HP0_FPD]
    make_bd_pins_external [get_bd_pins zynq_ultra_ps_e_0/saxihp0_fpd_aclk]
    make_bd_pins_external [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0]

    assign_bd_address

    # Rename ports to match the top module wrapper
    set_property name S_AXI_HP0_FPD [get_bd_intf_ports S_AXI_HP0_FPD_0]
    set_property name saxihp0_fpd_aclk [get_bd_ports saxihp0_fpd_aclk_0]
    set_property name pl_resetn0 [get_bd_ports pl_resetn0_0]

    # The interface FREQ_HZ is read-only: it follows the associated clock
    set_property CONFIG.ASSOCIATED_BUSIF {S_AXI_HP0_FPD} [get_bd_ports saxihp0_fpd_aclk]
    set_property CONFIG.FREQ_HZ 100000000 [get_bd_ports saxihp0_fpd_aclk]

    validate_bd_design
    save_bd_design
    generate_target all [get_files system.bd]
    set wrapper_path [make_wrapper -files [get_files system.bd] -top]
    read_verilog $wrapper_path
}

}

read_verilog vivado/$BOARD/iob_xilinx_clock_wizard.v
read_verilog vivado/$BOARD/iob_clock_wizard.v
if {[file exists vivado/$BOARD/iob_reset_sync.v]} {
    read_verilog vivado/$BOARD/iob_reset_sync.v
}
# iob_sync_reg_a is dependency of iob_reset_sync but may not exist in fpga folder if it is defined elsewhere (like hardware/src/)
if {[file exists vivado/$BOARD/iob_sync_reg_a.v]} {
    read_verilog vivado/$BOARD/iob_sync_reg_a.v
}

if {[file exists "vivado/$BOARD/auto_board.sdc"]} {
    read_xdc vivado/$BOARD/auto_board.sdc
}
