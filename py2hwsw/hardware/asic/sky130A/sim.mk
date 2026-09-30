# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: GPL-3.0-only

# This makefile segment is used at build-time, for gate-level simulation of an
# ASIC design implemented with LibreLane. It adds the Verilog simulation models
# of the sky130 standard cell library to the sources of the simulation.

# Root of the PDKs installed with Ciel
PDK_ROOT?=$(HOME)/.ciel

# Standard cell library and SRAM macros of sky130
ASIC_SCL?=sky130_fd_sc_hd
SKY130_SRAMS?=sky130_sram_macros

SCL_MODEL_DIR=$(PDK_ROOT)/$(ASIC_PDK)/libs.ref/$(ASIC_SCL)/verilog
SRAM_MODEL_DIR=$(PDK_ROOT)/$(ASIC_PDK)/libs.ref/$(SKY130_SRAMS)/verilog

# The models of the standard cells of this PDK are selected by these macros:
# the place-and-route netlists connect the power pins of the cells, and only
# the functional models simulate the logic of the cells.
GATE_DEFINES=USE_POWER_PINS FUNCTIONAL

# The cell models use the user defined primitives of 'primitives.v' (e.g. the
# flip-flop and mux primitives of the library), which must be compiled first
ifneq ($(wildcard $(SCL_MODEL_DIR)/$(ASIC_SCL).v),)
VSRC+= $(SCL_MODEL_DIR)/primitives.v $(SCL_MODEL_DIR)/$(ASIC_SCL).v
else
$(error Standard cell models '$(SCL_MODEL_DIR)/$(ASIC_SCL).v' not found. Install the '$(ASIC_PDK)' PDK with ciel.)
endif

# The SRAM macros are only used by designs with memory macros
ifneq ($(wildcard $(SRAM_MODEL_DIR)/$(SKY130_SRAMS).v),)
ifneq ($(WITH_SRAMS),0)
VSRC+= $(wildcard $(SRAM_MODEL_DIR)/sky130_sram_*.v)
endif
endif
