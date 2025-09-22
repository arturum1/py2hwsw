# SPDX-FileCopyrightText: 2025 IObundle
#
# SPDX-License-Identifier: MIT

# Vitis Python script to program PS7 CPU of Zynq boards

import sys
import xsdb


def program_ps7_cpu(fsbl_elf_path, elf_path):
    # Start debug session
    session = xsdb.start_debug_session()

    # Connect to local hardware server (omit url for local)
    session.connect()

    # Select CPU target by filtering name that matches ARM Cortex-A9 (PS7)
    target = session.targets("--set", filter="name =~ ARM Cortex-A9 MPCore #0")
    print("Selected target:", target)

    # Reset system (optional)
    # session.rst(type="system")

    # Program FSBL ELF which performs PS7 init and DDR release
    print(f"Downloading FSBL ELF: {fsbl_elf_path}")
    session.dow(fsbl_elf_path)
    # Run the program
    session.con()

    # Download ELF to the target CPU
    print(f"Downloading ELF: {elf_path}")
    session.dow(elf_path)
    # Run the program
    session.con()

    print("Program running on PS7 CPU.")

    # If needed, stop or halt target with session.stop() or session.halt()


if __name__ == "__main__":
    fsbl_file_path = sys.argv[1]
    elf_file_path = sys.argv[2]
    program_ps7_cpu(fsbl_file_path, elf_file_path)
