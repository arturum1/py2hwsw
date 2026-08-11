# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: GPL-3.0-only

## System Clock
# System clock already created in auto_board.sdc
set_property PACKAGE_PIN F23 [get_ports {c0_sys_clk_clk_p_i}]
set_property IOSTANDARD LVDS [get_ports {c0_sys_clk_clk_p_i}]
set_property PACKAGE_PIN E23 [get_ports {c0_sys_clk_clk_n_i}]
set_property IOSTANDARD LVDS [get_ports {c0_sys_clk_clk_n_i}]

set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property CFGBVS GND [current_design]

## USB-UART Interface (UART2, PL side)
set_property PACKAGE_PIN C19 [get_ports {txd_o}]
set_property IOSTANDARD LVCMOS18 [get_ports {txd_o}]
set_property PACKAGE_PIN A20 [get_ports {rxd_i}]
set_property IOSTANDARD LVCMOS18 [get_ports {rxd_i}]

set_false_path -from [get_ports {rxd_i}]
set_false_path -to [get_ports {txd_o}]

####### User PUSH Switches
set_property PACKAGE_PIN M11 [get_ports {areset_i}]
set_property IOSTANDARD LVCMOS33 [get_ports {areset_i}]

####### Reset
# On a global buffer, arst can fail to reach the flip-flops during startup
set_property CLOCK_BUFFER_TYPE NONE [get_nets -hierarchical arst]
