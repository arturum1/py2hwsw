# SPDX-FileCopyrightText: 2025 IObundle
#
# SPDX-License-Identifier: MIT

# This makefile is used at build-time

FPGA_SERVER=$(VIVADO_SERVER)
FPGA_USER=$(VIVADO_USER)
FPGA_SSH_FLAGS=$(VIVADO_SSH_FLAGS)
FPGA_SCP_FLAGS=$(VIVADO_SCP_FLAGS)
FPGA_SYNC_FLAGS=$(VIVADO_SYNC_FLAGS)
USE_EXTMEM ?=0
USE_ETHERNET ?=0

ifeq ($(IS_FPGA),1)
FPGA_OBJ=$(FPGA_TOP).bit
else
FPGA_OBJ=$(FPGA_TOP)_netlist.v
FPGA_STUB=$(FPGA_TOP)_stub.v
endif


FPGA_PROG=vivado -nojournal -log vivado.log -mode batch -source vivado/prog.tcl -tclargs $(FPGA_TOP).bit "$(BOARD_DEVICE_ID) " "$(HW_TARGET) "

ifneq ($(FSBL),)
# Program Zynq PS7 CPU as well
FPGA_PROG+= && vitis --source vivado/vitis_prog.py $(FSBL)
endif

# work-around for http://svn.clifford.at/handicraft/2016/vivadosig11
export RDI_VERBOSE = False

VIVADO_FLAGS= -nojournal -log reports/vivado.log -mode batch -source vivado/build.tcl -tclargs $(NAME) $(FPGA_TOP) $(CSR_IF) $(BOARD) "$(VSRC)" " $(INCLUDE_DIRS)" $(IS_FPGA) $(USE_EXTMEM) $(USE_ETHERNET)

VITIS_FLAGS= --source vivado/vitis_build.py $(NAME)

$(FPGA_OBJ): $(VSRC) $(VHDR) $(wildcard $(BOARD)/*.sdc)
	mkdir -p reports && vivado $(VIVADO_FLAGS) 

$(FSBL): $(FPGA_OBJ)
	vitis $(VITIS_FLAGS)
	mv vitis_ws/$(NAME)/build/$(NAME).elf $(FSBL)

vivado-clean:
	@rm -rf .Xil

.PHONY: vivado-clean
