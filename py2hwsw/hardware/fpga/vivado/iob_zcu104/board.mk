# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: GPL-3.0-only

BOARD_SERVER=$(ZCU104_SERVER)
BOARD_USER=$(ZCU104_USER)
BOARD_SERIAL_PORT=$(ZCU104_SERIAL_PORT)

# Only the external memory build has a PS, and its DDR controller needs
# psu_init, which Vivado cannot run
ifeq ($(USE_EXTMEM),1)
FPGA_PROG = xsct vivado/$(BOARD)/zynqmp_prog.tcl $(FPGA_TOP) $(BOARD_DEVICE_ID) $(BOARD)

FPGA_EXTRA_DIRS = .gen
else
FPGA_PROG = vivado -nojournal -log vivado.log -mode batch -source vivado/$(BOARD)/prog.tcl -tclargs $(FPGA_TOP) $(BOARD_DEVICE_ID)
endif
