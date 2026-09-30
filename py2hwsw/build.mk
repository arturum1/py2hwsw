# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: GPL-3.0-only

# This file is copied to the root of the build directory and becomes the top Makefile.

SHELL:=bash

export SIMULATOR ?= icarus
export SYNTHESIZER ?= yosys
export BOARD ?= iob_cyclonev_gt_dk
export LINTER ?= spyglass

ROOT_DIR :=.
include config_build.mk

SIM_DIR := hardware/simulation
BOARD_DIR := $(shell find hardware/fpga -name $(BOARD) -type d -print -quit)
SYN_DIR=hardware/syn

ifeq (fpga,$(findstring fpga,$(MAKECMDGOALS)))
  USE_FPGA = 1
ifeq ($(BOARD_DIR),)
  $(error ERROR: Board directory for board '$(BOARD)' not found under hardware/fpga/! Is the board name correct? )
endif
endif

# 
# EMBEDDED SOFTWARE
#
SW_DIR=software
sw-build:
	make -C $(SW_DIR) build USE_FPGA=$(USE_FPGA)

sw-clean:
	if [ -f "$(SW_DIR)/Makefile" ]; then make -C $(SW_DIR) clean; fi

#this target is not the same as sw-build because this one will cause USE_FPGA=1 to be true (this will affect software compilation)
fpga-sw-build: sw-build


#
# PC EMUL
#
pc-emul-build: sw-build
	make -C $(SW_DIR) build_emul

pc-emul-run:
	make -C $(SW_DIR) run_emul

pc-emul-test:
	make -C $(SW_DIR) test_emul

pc-emul-clean:
	if [ -f "$(SW_DIR)/Makefile" ]; then make -C $(SW_DIR) clean; fi


#
# LINT
#

LINT_DIR=hardware/lint
lint-run:
ifeq ($(USE_FPGA),1)
	make -C $(LINT_DIR) run BOARD_DIR=$(BOARD_DIR)
else
	make -C $(LINT_DIR) run
endif

lint-clean:
	if [ -f "$(LINT_DIR)/Makefile" ]; then make -C $(LINT_DIR) clean; fi

lint-test:
	make lint-run LINTER=spyglass
	make lint-run LINTER=alint


#
# SIMULATE
#

sim-build: sw-build
	make -C $(SIM_DIR) -j1 build

sim-run: sw-build
	make -C $(SIM_DIR) -j1 run

sim-waves:
	make -C $(SIM_DIR) waves

sim-test:
	make -C $(SIM_DIR) test

sim-debug: 
	make -C $(SIM_DIR) debug

sim-clean:
	if [ -f "$(SIM_DIR)/Makefile" ]; then make -C $(SIM_DIR) clean; fi

sim-cov: sim-clean
	make -C $(SIM_DIR) -j1 run COV=1


#
# FPGA
#
FPGA_DIR=hardware/fpga
fpga-build:
	make -C $(FPGA_DIR) -j1 build USE_FPGA=$(USE_FPGA)

fpga-run:
	make -C $(FPGA_DIR) -j1 run USE_FPGA=$(USE_FPGA)

fpga-test:
	make -C $(FPGA_DIR) test USE_FPGA=$(USE_FPGA)

fpga-debug:
	echo "BOARD=$(BOARD)"
	make -C $(FPGA_DIR) debug

fpga-gui:
	make -C $(FPGA_DIR) gui BOARD=$(BOARD) USE_FPGA=$(USE_FPGA)

fpga-debug-ila:
	make -C $(FPGA_DIR) debug-ila BOARD=$(BOARD) USE_FPGA=$(USE_FPGA)

fpga-clean:
	if [ -f "$(FPGA_DIR)/Makefile" ]; then make -C $(FPGA_DIR) clean; fi

#
# SYN
#
syn-build:
	make -C $(SYN_DIR) build

syn-clean:
	if [ -f "$(SYN_DIR)/Makefile" ]; then make -C $(SYN_DIR) clean; fi

syn-test: syn-clean syn-build

#
# ASIC
#
ASIC_DIR=hardware/asic
# The ASIC flow requires the 'librelane' tool (see py2hwsw/lib/default.nix)
ASIC_AVAILABLE := $(shell which librelane 2>/dev/null)
asic-build:
	make -C $(ASIC_DIR) build

asic-drc:
	make -C $(ASIC_DIR) drc

asic-lvs:
	make -C $(ASIC_DIR) lvs

asic-sta:
	make -C $(ASIC_DIR) sta

asic-gui:
	make -C $(ASIC_DIR) gui

asic-sim:
	make -C $(ASIC_DIR) sim-run

asic-report:
	make -C $(ASIC_DIR) report

asic-clean:
	if [ -f "$(ASIC_DIR)/Makefile" ]; then make -C $(ASIC_DIR) clean; fi

# The ASIC flow is only part of the test suite if the tool is available
ifeq ($(ASIC_AVAILABLE),)
asic-test:
	@echo "Note: Skipping ASIC test, 'librelane' not found in PATH."
else
asic-test: asic-build asic-report asic-sim
endif

#
# DOCUMENT
#
DOC_DIR=document
doc-build:
	make -C $(DOC_DIR) build

doc-view:
	make -C $(DOC_DIR) view

doc-debug: 
	make -C $(DOC_DIR) debug

doc-clean:
	if [ -f "$(DOC_DIR)/Makefile" ]; then make -C $(DOC_DIR) clean; fi

ifneq ($(wildcard document/tsrc),)
doc-test: doc-clean
	make -C $(DOC_DIR) test
else
doc-test:
endif


#
# TEST
#
test: sim-test fpga-test doc-test

ptest: dtest lint-test sim-cov

dtest: test syn-test asic-test



#
# CLEAN
#

clean: sw-clean pc-emul-clean lint-clean sim-clean fpga-clean syn-clean asic-clean doc-clean


.PHONY: sw-build sw-clean \
	pc-emul-build pc-emul-run pc-emul-clean \
	lint-test lint-run lint-clean \
	sim-build sim-run sim-debug sim-clean \
	fpga-build fpga-debug fpga-gui fpga-clean \
	syn-build syn-clean \
	asic-build asic-drc asic-lvs asic-sta asic-gui asic-sim asic-report asic-clean \
	doc-build doc-view doc-debug doc-test doc-clean \
	test clean debug

