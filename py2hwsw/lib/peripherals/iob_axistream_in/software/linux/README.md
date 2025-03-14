<!--
SPDX-FileCopyrightText: 2025 IObundle

SPDX-License-Identifier: MIT
-->

# IOb AXIStream In Linux Kernel Drivers
- Structure:
    - `drivers/`: directory with linux kernel module drivers for
      iob_axistream_in
        - `iob_axistream_in_main.c`: driver source
        - `[iob_axistream_in.h]` and `[iob_axistream_in_sysfs.h]`: header files
          generated by:
        ```bash
        python3 .path/to/iob-linux/scripts/drivers.py iob_axistream_in -o [output_dir]
        ```
        - `driver.mk`: makefile segment with `iob_axistream_in-obj:` target for driver
          compilation
    - `iob_axistream_in.dts`: device tree template with iob_axistream_in node
        - manually add the `axistream_in` node to the system device tree so the
          iob_axistream_in is recognized by the linux kernel
