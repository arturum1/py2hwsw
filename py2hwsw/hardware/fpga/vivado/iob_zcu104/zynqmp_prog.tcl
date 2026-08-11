# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: GPL-3.0-only

# Zynq UltraScale+ Programming Script for XSCT
set FPGA_TOP [lindex $argv 0]
set DEVICE_ID [lindex $argv 1]
set BOARD [lindex $argv 2]

connect

# 1. Reset System first to clean PS state
targets -set -nocase -filter {name =~ "*PSU*"}
puts "--- Resetting System ---"
rst -system
after 1000

# 2. Program the PL
targets -set -nocase -filter {name =~ "PL"}
puts "--- Programming PL ---"
fpga "$FPGA_TOP.bit"

# 3. Initialize PS
targets -set -nocase -filter {name =~ "*PSU*"}
puts "--- Initializing PS ---"
# Find psu_init.tcl. In Py2HWSW it should be in the generated .gen directory.
set PSU_INIT_FILE [glob -nocomplain -directory . -- .gen/sources_1/bd/system/ip/*/psu_init.tcl]
if {[llength $PSU_INIT_FILE] == 0} {
    # Fallback to alternative location
    set PSU_INIT_FILE [glob -nocomplain -directory . -- ip/system/ip/*/psu_init.tcl]
}
if {[llength $PSU_INIT_FILE] == 0} {
    # Last resort search
    set PSU_INIT_FILE [glob -nocomplain -directory . -- */*/*/*/psu_init.tcl]
}

if {[llength $PSU_INIT_FILE] > 0} {
    set PSU_INIT_FILE [lindex $PSU_INIT_FILE 0]
    puts "--- Sourcing $PSU_INIT_FILE ---"
    source $PSU_INIT_FILE
    psu_init
    after 500
} else {
    puts "WARNING: psu_init.tcl not found!"
}

# 4. Unblock AFI / Enable Level Shifters
puts "--- Enabling Level Shifters ---"
if {[info procs psu_ps_pl_isolation_removal] ne ""} { psu_ps_pl_isolation_removal }
if {[info procs psu_ps_pl_reset_config] ne ""} { psu_ps_pl_reset_config }

# 5. Load and Run PS Application (if ELF exists)
# In Py2HWSW, software is usually built in software/ folder.
set elf_path "../../software/ps_app.elf"
if {[file exists $elf_path]} {
    puts "--- Loading PS Application: $elf_path ---"
    targets -set -nocase -filter {name =~ "*Cortex-A53 #0*"}
    dow $elf_path
    puts "--- Running PS Application ---"
    con
} else {
    puts "INFO: No PS application found at $elf_path"
}

puts "--- Deployment Complete ---"
exit
