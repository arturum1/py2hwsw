#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: MIT

set -e

#find directories containing testbenches
TBS=`find ${LIB_DIR} | grep _tb.v | grep -v include | grep -v submodules`

FILTER_OUT_TBS=""
#for debug
#FILTER_OUT_TBS="iob_div_pipe iob_div_subshift iob_div_subshift_frac iob_ctls iob_prio_enc iob_and iob_aoi iob_csrs_demo iob_axis2ahb iob_iob_s_axi_m iob_dma iob_pulse_gen iob_fifo_async iob_fifo_sync iob_ram_2p iob_ram_at2p iob_ram_atdp iob_ram_atdp_be iob_ram_sp iob_ram_sp_be iob_ram_sp_se iob_ram_t2p iob_ram_t2p_be iob_ram_t2p_tiled iob_ram_tdp iob_ram_tdp_be iob_ram_tdp_be_xil iob_rom_2p iob_rom_atdp iob_rom_sp iob_rom_tdp iob_regarray_sp iob_shift_reg iob_system iob_system_linux iob_axistream_in iob_macc iob_timer iob_uart"

TBS_FILTERED=()

# Filter out Testbenches from cores specified in FILTER_OUT_TBS
for tb in $TBS; do
  skip=0
  for f in $FILTER_OUT_TBS; do
    if [[ $tb == *"$f/hardware/simulation"* ]]; then
      skip=1
      break
    fi
  done

  [[ $skip -eq 0 ]] && TBS_FILTERED+=("$tb")
done

# If you want it as a space-separated string:
TBS_FILTERED="${TBS_FILTERED[*]}"

echo $TBS_FILTERED

#extract respective directories
for i in $TBS_FILTERED; do TB_DIRS+=" `dirname $i`" ; done

#extract respective modules - go back from MODULE/hardware/simulation/src
for i in $TB_DIRS; do MODULES+=" `basename $(builtin cd $i/../../..; pwd)`" ; done

#test first argument is "clean", run make clean for all modules and exit
if [ "$1" == "clean" ]; then
    for i in $MODULES; do 
        DEFAULT_BUILD_DIR=`py2hwsw $i print_build_dir`
        make clean CORE=$i BUILD_DIR=../../${DEFAULT_BUILD_DIR}
    done
    exit 0
fi

#test if first argument is test and run all tests
if [ "$1" == "test" ]; then
    for i in $MODULES; do
        echo -e "\n\033[1;33mTesting module '${i}'\033[0m"
        DEFAULT_BUILD_DIR=`py2hwsw $i print_build_dir`
        make -f ${LIB_DIR}/Makefile clean setup CORE=$i BUILD_DIR=../../${DEFAULT_BUILD_DIR}
        make -C ../../${DEFAULT_BUILD_DIR} sim-run
    done
    exit 0
fi

#test if first argument is "build" and run build for single module
if [ "$1" == "build" ]; then
    DEFAULT_BUILD_DIR=`py2hwsw $2 print_build_dir`
    make clean setup CORE=$2 BUILD_DIR=../../${DEFAULT_BUILD_DIR}
    make -C ../../${DEFAULT_BUILD_DIR} sim-build
    exit 0
fi

#run single test
DEFAULT_BUILD_DIR=`py2hwsw $1 print_build_dir`
make clean setup CORE=$1 BUILD_DIR=../../${DEFAULT_BUILD_DIR}
make -C ../../${DEFAULT_BUILD_DIR} sim-run VCD=$VCD
