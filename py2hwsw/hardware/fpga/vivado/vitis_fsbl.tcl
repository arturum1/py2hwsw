# SPDX-FileCopyrightText: 2025 IObundle
#
# SPDX-License-Identifier: MIT

# Vitis tcl script to generate FSBL for Zynq boards
#
#extract cli positional args
set vars {NAME}
foreach var $vars arg $argv {
    set $var $arg
    puts "$var = $arg"
}

# Open a workspace in ./vitis_ws directory
setws ./vitis_ws

# Create a platform project from vivado's exported hardware
platform create -name hw_platform -hw hw_platform.xsa

# Create FSBL application project using the Zynq FSBL template.
app create -name $NAME -platform hw_platform -template {Zynq FSBL}

# Build FSBL. Will generate ELF in: <workspace>/<app_name>/Debug/<app_name>.elf
app build -name $NAME

# Optionally, package BOOT.bin (contains FSBL and bitstream, ready to include in SD card)
# bsp create -name fsbl_bsp -platform hw_platform
# bootgen -arch zynq -image boot_image.bif -o BOOT.bin
