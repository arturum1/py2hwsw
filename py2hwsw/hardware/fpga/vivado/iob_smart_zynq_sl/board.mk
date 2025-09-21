# SPDX-FileCopyrightText: 2025 IObundle
#
# SPDX-License-Identifier: MIT

BOARD_SERVER=$(SMART_SERVER)
BOARD_USER=$(SMART_USER)
BOARD_SERIAL_PORT=$(SMART_SERIAL_PORT)
FSBL=$(NAME)_fsbl.elf
HW_TARGET=*/xilinx_tcf/Xilinx/*

# Smart Zynq SL has two hardware devices:
# arm_dap_0
# xc7z020_1
# Select FPGA device ID = 1
BOARD_DEVICE_ID=1
