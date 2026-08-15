# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: GPL-3.0-only

BOARD_SERVER=$(CYC5_SERVER)
BOARD_USER=$(CYC5_USER)
BOARD_SERIAL_PORT=$(CYC5_SERIAL_PORT)

ifneq ($(wildcard $(FPGA_TOOL)/$(BOARD)/iob_reset_sync.v),)
VSRC+=$(FPGA_TOOL)/$(BOARD)/iob_reset_sync.v
endif

ifeq ($(USE_EXTMEM),1)
VSRC+=$(FPGA_TOOL)/$(BOARD)/alt_ddr3.qsys
endif
