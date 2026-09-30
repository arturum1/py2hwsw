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
ASIC_RUN_TAG ?= $(NAME)
# Maximum number of threads/processes used by the flow.
ASIC_JOBS ?= 4
# Name of the LibreLane configuration file generated during setup.
ASIC_CONFIG ?= config.json

ASIC_FLOW := $(shell echo $(ASIC_FLOW) | tr 'A-Z' 'a-z')
ASIC_FLAGS += -f $(ASIC_FLOW) --design-dir . -j $(ASIC_JOBS)

# Extra LibreLane configuration overrides, e.g.
#   make run ASIC_EXTRA_FLAGS="-c IO_DELAY_CONSTRAINT=10"
# The values are also used by the constraints in 'impl.sdc'/'signoff.sdc'.
ASIC_EXTRA_FLAGS ?=
ASIC_FLAGS += $(ASIC_EXTRA_FLAGS)

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

# Check that the tools and inputs are available before starting a long run
check:
	@which librelane >/dev/null || { echo "ERROR: 'librelane' not found in PATH."; exit 1; }
	@test -f $(ASIC_CONFIG) || { echo "ERROR: '$(ASIC_CONFIG)' not found. Re-run the setup."; exit 1; }
	@test -d ../src || { echo "ERROR: '../src' not found. Re-run the setup."; exit 1; }
	@test -n "$$(ls ../src/*.v 2>/dev/null)" || { echo "ERROR: no Verilog sources in '../src'."; exit 1; }

# Full RTL to GDSII implementation
build: check
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
NETLIST=runs/$(ASIC_RUN_TAG)/final/pnl/$(NAME).pnl.v
GATE_NETLIST=gate_sim/$(NAME).v
SIM_FLAGS := SYN=1 GATE_SYN_DIR=asic NODE=$(ASIC_PDK) ASIC_PDK=$(ASIC_PDK) GATE_NETLIST=../asic/$(GATE_NETLIST) TB=$(NAME)_tb TBTYPE=V

gate_netlist:
	@test -f $(NETLIST) || { echo "ERROR: netlist '$(NETLIST)' not found. Run 'make build' first."; exit 1; }
	python3 gate_sim_prep.py --netlist $(NETLIST) --out $(GATE_NETLIST)

# Name of the testbench file used in gate-level simulation. The testbench must
# instantiate the implemented module ($(NAME)), not a submodule of it.
ASIC_TB ?= $(NAME)_tb.v

check_tb:
	@test -f ../simulation/src/$(ASIC_TB) || { echo "ERROR: no testbench '../simulation/src/$(ASIC_TB)' found. Gate-level simulation needs a testbench that instantiates the implemented module."; exit 1; }

sim-build: gate_netlist check_tb
	@mkdir -p ../simulation/src_bak
	@find ../simulation/src -maxdepth 1 -name '*_tb.v' ! -name '$(ASIC_TB)' -exec mv {} ../simulation/src_bak/ \;
	$(MAKE) -C ../simulation $(SIM_FLAGS) build
	@mv ../simulation/src_bak/* ../simulation/src/ 2>/dev/null || true
	@rmdir ../simulation/src_bak 2>/dev/null || true

sim-run: gate_netlist check_tb
	@echo "Preparing gate-level simulation environment..."
	@mkdir -p ../simulation/src_bak
	@find ../simulation/src -maxdepth 1 -name '*_tb.v' ! -name '$(ASIC_TB)' -exec mv {} ../simulation/src_bak/ \;
	$(MAKE) -C ../simulation $(SIM_FLAGS) comp exec
	@echo "Restoring simulation sources..."
	@mv ../simulation/src_bak/* ../simulation/src/ 2>/dev/null || true
	@rmdir ../simulation/src_bak 2>/dev/null || true

sim: sim-run

# Generate the LaTeX table with the ASIC results for the documentation
report:
	python3 asic_report.py --runs_dir runs --run_tag $(ASIC_RUN_TAG) --out ../../document/tsrc

clean:
	rm -rf runs gate_sim
	rm -f $(ASIC_CONFIG)

.PHONY: check check_tb build run drc lvs sta gui gate_netlist sim-build sim-run sim report clean
