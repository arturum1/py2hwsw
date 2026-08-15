# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: GPL-3.0-only

GPIO_DIR:=../../..
include $(GPIO_DIR)/hardware/hardware.mk

FPGA_VSRC=$(addprefix ../, $(VSRC) )
FPGA_VHDR=$(addprefix ../, $(VHDR) )
FPGA_INCLUDE=$(addprefix ../, $(INCLUDE) )

$(FPGA_OBJ): $(CONSTRAINTS) $(VSRC) $(VHDR)
	mkdir -p $(FPGA_FAMILY)
	cd $(FPGA_FAMILY); ../build.sh "$(TOP_MODULE)" "$(FPGA_PART)" "$(FPGA_VSRC)" "$(FPGA_INCLUDE)" "$(DEFINE)"
