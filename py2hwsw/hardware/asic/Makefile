# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: GPL-3.0-only

# This file becomes the ASIC makefile when copied to the build directory.
# It drives LibreLane (https://github.com/librelane/librelane), the open source
# RTL-to-GDSII flow, to implement this core/system for an open source PDK.

SHELL:=bash

include ../../config_build.mk

# Flow selection: 'classic' goes from RTL to GDSII, 'optimizing' and the
# 'openin*' flows are debug/GUI flows.
ASIC_FLOW ?= classic
# Process design kit and standard cell library to target.
ASIC_PDK ?= sky130A
ASIC_SCL ?=
# Clock period (ns) of the design's main clock domain.
CLOCK_PERIOD ?= 10
# Name of the run directory under 'runs/'.
ASIC_RUN_TAG ?= $(DESIGN_NAME)
# Maximum number of threads/processes used by the flow.
ASIC_JOBS ?= 4
# Name of the LibreLane configuration file generated during setup.
ASIC_CONFIG ?= config.json

ASIC_FLOW := $(shell echo $(ASIC_FLOW) | tr 'A-Z' 'a-z')
ASIC_FLAGS += -f $(ASIC_FLOW) --design-dir . -j $(ASIC_JOBS)

# Name of the design in the generated configuration. It is the name of the
# top module of the design, which may be an ASIC wrapper of the core (e.g.
# 'iob_system_asic'). The name is read from the configuration file, which is
# generated during the setup of the core.
DESIGN_NAME := $(shell sed -n 's/.*"DESIGN_NAME"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' $(ASIC_CONFIG) 2>/dev/null)
ifeq ($(strip $(DESIGN_NAME)),)
DESIGN_NAME := $(NAME)
endif

# Extra LibreLane configuration overrides, e.g.
#   make run ASIC_EXTRA_FLAGS="-c IO_DELAY_CONSTRAINT=10"
# The values are also used by the constraints in 'impl.sdc'/'signoff.sdc'.
ASIC_EXTRA_FLAGS ?=
ASIC_FLAGS += $(ASIC_EXTRA_FLAGS)

# Last step of the flow to run (e.g. 'Yosys.Synthesis'). All the steps of the
# flow are run when it is empty.
ASIC_FLOW_TO ?=
ifneq ($(strip $(ASIC_FLOW_TO)),)
ASIC_FLAGS += --to $(ASIC_FLOW_TO)
endif

ifneq ($(strip $(ASIC_PDK)),)
ASIC_FLAGS += -p $(ASIC_PDK)
endif
ifneq ($(strip $(ASIC_SCL)),)
ASIC_FLAGS += -s $(ASIC_SCL)
endif
ifneq ($(strip $(CLOCK_PERIOD)),)
ASIC_FLAGS += -c CLOCK_PERIOD=$(CLOCK_PERIOD)
endif
ifneq ($(strip $(ASIC_RUN_TAG)),)
ASIC_FLAGS += --run-tag $(ASIC_RUN_TAG)
endif

# Include core/user specific ASIC settings, if any
ifneq ($(wildcard asic_build.mk),)
include asic_build.mk
endif

# Bootrom/firmware hex files (mirrors sim_build.mk). The memories of the
# design are initialized by the synthesis, which reads these files, so they
# must be in this directory. Only the systems that provide a software build
# define these targets, so both the include and the dependencies are guarded.
ROOT_DIR := ../..
ifneq ($(wildcard $(ROOT_DIR)/software/sw_build.mk),)
include $(ROOT_DIR)/software/sw_build.mk
ifneq ($(shell grep -c "^$(NAME)_bootrom.hex:" $(ROOT_DIR)/software/sw_build.mk 2>/dev/null),0)
BUILD_DEPS += $(NAME)_bootrom.hex
endif
ifneq ($(shell grep -c "^$(NAME)_firmware.hex:" $(ROOT_DIR)/software/sw_build.mk 2>/dev/null),0)
BUILD_DEPS += $(NAME)_firmware.hex
endif
endif

# Check that the tools and inputs are available before starting a long run
check:
	@which librelane >/dev/null || { echo "ERROR: 'librelane' not found in PATH."; exit 1; }
	@test -f $(ASIC_CONFIG) || { echo "ERROR: '$(ASIC_CONFIG)' not found. Re-run the setup."; exit 1; }
	@test -d ../src || { echo "ERROR: '../src' not found. Re-run the setup."; exit 1; }
	@test -n "$$(ls ../src/*.v 2>/dev/null)" || { echo "ERROR: no Verilog sources in '../src'."; exit 1; }

# The design may read memory initialization files (e.g. the branch predictor
# history of the CPU). The synthesis reads them from the design directory, so
# they are copied from the simulation directory, where the setup of the core
# puts them.
init_mems:
	@cp -f ../simulation/*.bin . 2>/dev/null || true

# Full RTL to GDSII implementation
build: check init_mems $(BUILD_DEPS)
	librelane $(ASIC_CONFIG) $(ASIC_FLAGS)

run: build

# Run only some of the steps of a previous run (requires a completed build)
LAST_RUN_FLAGS := $(ASIC_CONFIG) --last-run -f $(ASIC_FLOW) -p $(ASIC_PDK) --design-dir .

drc:
	librelane $(LAST_RUN_FLAGS) --from KLayout.DRC --to Magic.DRC

lvs:
	librelane $(LAST_RUN_FLAGS) --only Netgen.LVS

sta:
	librelane $(LAST_RUN_FLAGS) --only OpenROAD.STAPostPNR

# Interactive layout/routing viewer (requires a previous run)
gui:
	librelane $(ASIC_CONFIG) --last-run -f openinklayout --design-dir . -p $(ASIC_PDK)

# Gate-level simulation of the place-and-route netlist. The cell models and the
# netlist are added to the simulation of the core's testbench by the
# 'hardware/asic/$(ASIC_PDK)/sim.mk' makefile segment.
# The netlist of a run is written by the last step of the flow, whose
# directory name contains a step counter, so it is looked up with a glob.
NETLIST_DIR=runs/$(ASIC_RUN_TAG)/final
GATE_NETLIST=gate_sim/$(DESIGN_NAME).v

# Name of the testbench file used in gate-level simulation. The testbench must
# instantiate the implemented module ($(DESIGN_NAME)), not a submodule of it.
ASIC_TB ?= $(DESIGN_NAME)_tb.v
# Type of the testbench ('V' for Verilog, 'UVM' for SystemVerilog/UVM)
ASIC_TBTYPE ?= V
# Directory of the ASIC flow that holds the testbench. The testbench is not
# part of the design, so it is kept out of the directories that the flow reads
# as Verilog sources (the testbenches are not valid Verilog for synthesis).
ASIC_TB_DIR ?= sim
ASIC_TB_PATH = $(ASIC_TB_DIR)/$(ASIC_TB)

SIM_FLAGS := SYN=1 GATE_SYN_DIR=asic NODE=$(ASIC_PDK) ASIC_PDK=$(ASIC_PDK) \
	GATE_NETLIST=../asic/$(GATE_NETLIST) TB=$(basename $(ASIC_TB)) TBTYPE=$(ASIC_TBTYPE)

gate_netlist:
	@NETLIST=$$(ls $(NETLIST_DIR)/pnl/$(DESIGN_NAME).pnl.v 2>/dev/null | head -1); \
	if [ -z "$$NETLIST" ]; then \
		NETLIST=$$(ls $(NETLIST_DIR)/*/pnl/$(DESIGN_NAME).pnl.v 2>/dev/null | head -1); \
	fi; \
	if [ -z "$$NETLIST" ]; then \
		echo "ERROR: netlist of '$(DESIGN_NAME)' not found in '$(NETLIST_DIR)'. Run 'make build' first."; exit 1; \
	fi; \
	echo "Preparing netlist '$$NETLIST'..."; \
	python3 gate_sim_prep.py --netlist "$$NETLIST" --out $(GATE_NETLIST)

check_tb:
	@test -f ../simulation/src/$(ASIC_TB) || test -f $(ASIC_TB_PATH) || { echo "ERROR: no testbench '$(ASIC_TB)' found. Gate-level simulation needs a testbench that instantiates the implemented module."; exit 1; }

# The testbench of the ASIC flow may be stored in the testbench directory of
# the ASIC flow, instead of in the simulation sources. It is copied there for
# the duration of the simulation, and removed afterwards, so that it is not
# compiled by the RTL simulation, which does not have the ASIC wrapper of the
# design.
TB_COPIED_MARKER=.asic_tb_copied

prepare_tb:
	@if [ -f $(ASIC_TB_PATH) ] && [ ! -f ../simulation/src/$(ASIC_TB) ]; then \
		cp $(ASIC_TB_PATH) ../simulation/src/$(ASIC_TB) && touch $(TB_COPIED_MARKER); \
	fi

restore_tb:
	@if [ -f $(TB_COPIED_MARKER) ]; then rm -f ../simulation/src/$(ASIC_TB) $(TB_COPIED_MARKER); fi

sim-build: gate_netlist check_tb
	@mkdir -p ../simulation/src_bak
	@find ../simulation/src -maxdepth 1 -name '*_tb.v' ! -name '$(ASIC_TB)' -exec mv {} ../simulation/src_bak/ \;
	@$(MAKE) --no-print-directory prepare_tb
	$(MAKE) -C ../simulation $(SIM_FLAGS) build
	@$(MAKE) --no-print-directory restore_tb
	@mv ../simulation/src_bak/* ../simulation/src/ 2>/dev/null || true
	@rmdir ../simulation/src_bak 2>/dev/null || true

sim-run: gate_netlist check_tb
	@echo "Preparing gate-level simulation environment..."
	@mkdir -p ../simulation/src_bak
	@find ../simulation/src -maxdepth 1 -name '*_tb.v' ! -name '$(ASIC_TB)' -exec mv {} ../simulation/src_bak/ \;
	@$(MAKE) --no-print-directory prepare_tb
	$(MAKE) -C ../simulation $(SIM_FLAGS) comp exec
	@$(MAKE) --no-print-directory restore_tb
	@echo "Restoring simulation sources..."
	@mv ../simulation/src_bak/* ../simulation/src/ 2>/dev/null || true
	@rmdir ../simulation/src_bak 2>/dev/null || true
	@grep -q "Test passed!" ../simulation/test.log || { echo "ERROR: gate-level simulation failed."; exit 1; }
	@echo "Gate-level simulation passed."

sim: sim-run

# Generate the LaTeX table with the ASIC results for the documentation
report:
	python3 asic_report.py --runs_dir runs --run_tag $(ASIC_RUN_TAG) --out ../../document/tsrc

clean:
	rm -rf runs gate_sim
	rm -f $(ASIC_CONFIG)

.PHONY: check check_tb build run drc lvs sta gui gate_netlist prepare_tb restore_tb sim-build sim-run sim report clean init_mems
