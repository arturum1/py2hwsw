# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: GPL-3.0-only

create_clock -name "clk" -period 20.0 [get_ports {clk_i}]
#create_clock -period 40 [get_ports {enet_rx_clk_i}]
