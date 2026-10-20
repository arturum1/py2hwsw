#!/usr/bin/env python3

# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: GPL-3.0-only

"""Generate the LibreLane configuration file for the ASIC flow.

The LibreLane configuration (JSON) is written to
'<build_dir>/hardware/asic/config.json' and describes the design to the flow:
its name, its Verilog sources, its clock, and the technology to use.
"""

import json
import os
import re

from iob_colors import ENDC, FAIL, INFO, OK, WARNING

# Power/ground net names of the supported PDK families
PDK_POWER_NETS = {
    "sky130": (["VPWR"], ["VGND"]),
    "gf180mcu": (["VDD"], ["VSS"]),
    "ihp-sg13g2": (["VDD"], ["VSS"]),
}

# Port names that look like a clock input, for example 'clk_i' or 'wb_clk_i'
CLOCK_PORT_RE = re.compile(r"^(?:[a-z][a-z0-9]*_)*clk(?:_i)?$")
# Port names that must never be used as a clock
NON_CLOCK_PORT_RE = re.compile(r"^cke|^clk(en|gate)|^clk_gating|^tb_clk")

# The flow writes this file to catch accidental dangling-input issues at the
# top level. LibreLane's own blackbox stub file has no 'timescale directive,
# which makes Verilator emit a TIMESCALEMOD warning per module in it.
DEFAULT_LINTER_DISABLE_WARNINGS = ["TIMESCALEMOD"]

# Maximum fanout of a net, used by the 'impl.sdc' template. The sky130 standard
# cell libraries are not strong enough to drive the default (unlimited) fanout
# nets of the RTL, and the post-layout timing reports max slew violations on the
# slowest corners if no limit is set. A lower limit makes the buffer trees of
# the high fanout nets (e.g. clock enables) much deeper, which the resizer then
# tries to fix by inserting delay cells, and it increases both the area and the
# critical path of the design without a gain in max slew violations.
DEFAULT_MAX_FANOUT = int(os.environ.get("MAX_FANOUT", 16))

# Core area utilization of the floorplan. The flow's default (50%) is used as
# the target for the cell area estimated after synthesis, and the resizer
# inserts many more buffers (for the max fanout and for timing repair) before
# detailed routing. On small designs that makes the placement unlegalizable
# ('Detailed placement failed'), so leave more room inside the core area.
DEFAULT_FP_CORE_UTIL = int(os.environ.get("FP_CORE_UTIL", 40))

# Mirroring the cells during detailed placement can leave overlaps that the
# flow is not able to legalize, which aborts the run.
DEFAULT_PL_OPTIMIZE_MIRRORING = os.environ.get("PL_OPTIMIZE_MIRRORING", "0")
# The PDK defaults restrict the timing violation checkers to the typical
# corners, which silently ignores violations at the slow (and fast) corners.
# Signoff is only meaningful when all reported corners are checked.
DEFAULT_TIMING_VIOLATION_CORNERS = ["*"]

# Percentage of the clock period reserved for the paths that go outside of the
# design. The PDK defaults reserve a fifth of the period, which is meant for
# chip-level I/O pads, board delays and the clock generator. The cores
# implemented by py2hwsw are blocks, whose interface signals are driven by the
# logic of the enclosing system, so a smaller budget gives a realistic
# constraint for the I/O paths of the design.
DEFAULT_IO_DELAY_CONSTRAINT = int(os.environ.get("IO_DELAY_CONSTRAINT", 10))


# Sky130 SRAM macro mapping: (addr_width, data_width) -> macro name
SKY130_MACROS = {
    # 1RW+1R macros - 32-bit data width
    (8, 32): "sky130_sram_1kbyte_1rw1r_32x256_8",  # 1KB, 256x32
    (9, 32): "sky130_sram_2kbyte_1rw1r_32x512_8",  # 2KB, 512x32
    (10, 32): "sky130_sram_4kbyte_1rw1r_32x1024_8",  # 4KB, 1024x32
    (11, 32): "sky130_sram_8kbyte_1rw1r_32x2048_8",  # 8KB, 2048x32
    (12, 32): "sky130_sram_16kbyte_1rw1r_32x4096_8",  # 16KB, 4096x32
    (13, 32): "sky130_sram_32kbyte_1rw1r_32x8192_8",  # 32KB, 8192x32
    # 1RW+1R macros - 8-bit data width
    (8, 8): "sky130_sram_1kbyte_1rw1r_8x1024_8",  # 1KB, 1024x8
    (9, 8): "sky130_sram_2kbyte_1rw1r_8x2048_8",  # 2KB, 2048x8
    (10, 8): "sky130_sram_4kbyte_1rw1r_8x4096_8",  # 4KB, 4096x8
    (11, 8): "sky130_sram_8kbyte_1rw1r_8x8192_8",  # 8KB, 8192x8
    (12, 8): "sky130_sram_16kbyte_1rw1r_8x16384_8",  # 16KB, 16384x8
    (13, 8): "sky130_sram_32kbyte_1rw1r_8x32768_8",  # 32KB, 32768x8
}


def get_pdk_power_nets(pdk):
    """Return the (VDD_NETS, GND_NETS) of a PDK variant name (e.g. 'sky130A')"""
    for family, nets in PDK_POWER_NETS.items():
        if pdk.startswith(family):
            return nets
    raise ValueError(f"Unknown PDK '{pdk}'. Supported: {list(PDK_POWER_NETS)}")


def get_top_module_ports(verilog_path, module_name):
    """Return the ports of a module as a list of (name, direction) tuples.

    The Verilog file is parsed (instead of using the core attributes) because
    the port names of the generated module are the result of the interface
    expansion (e.g. the 'clk_en_rst_s' port becomes the 'clk_i' pin).
    """
    if not os.path.isfile(verilog_path):
        raise FileNotFoundError(f"Top module Verilog file '{verilog_path}' not found")

    with open(verilog_path) as f:
        content = f.read()

    # Get the header (module declaration and port list) of the top module
    match = re.search(rf"\bmodule\s+{re.escape(module_name)}\b", content)
    if not match:
        raise ValueError(f"Module '{module_name}' not found in '{verilog_path}'")
    header = content[match.start() : content.find(");", match.start())]

    # Remove comments, to avoid matching commented out ports
    header = re.sub(r"//.*", "", header)

    ports = []
    for direction, decl in re.findall(
        r"\b(input|output|inout)\b([^,]*),", header, flags=re.DOTALL
    ):
        for name in decl.split("["):
            name = name.strip()
            if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", name) and name not in (
                "input",
                "output",
                "inout",
            ):
                ports.append((name, direction))
    return ports


def find_clock_ports(ports):
    """Return the names of the input ports that look like a clock input"""
    clock_ports = [
        name
        for name, direction in ports
        if direction == "input"
        and CLOCK_PORT_RE.match(name)
        and not NON_CLOCK_PORT_RE.match(name)
    ]
    if not clock_ports:
        raise ValueError("No clock input port found in the top module")
    return clock_ports


def map_memory_to_macro(addr_w, data_w):
    """Map memory size to nearest sky130 macro (round up).

    Returns (macro_name, actual_addr_w, actual_data_w)
    """
    for (a, d), macro in sorted(SKY130_MACROS.items()):
        if addr_w <= a and data_w <= d:
            return macro, a, d
    raise ValueError(
        f"No sky130 macro for {addr_w} addr / {data_w} data bits. "
        f"Available: {list(SKY130_MACROS.keys())}. Consider OpenRAM."
    )


def scan_memories(core):
    """Scan the core's hierarchy for memory instances.

    Returns list of dicts with memory info:
    - instance_name
    - type (iob_ram_t2p, iob_ram_t2p_be, iob_rom_sp, etc.)
    - addr_w, data_w
    - parameters
    """
    memories = []

    def is_mem_core(name):
        return name.startswith("iob_ram_") or name.startswith("iob_rom_")

    def scan_subblocks(subblocks):
        for subblock in subblocks:
            # Handle both dict and string elements
            if not isinstance(subblock, dict):
                continue
            core_name = subblock.get("core", "")
            if is_mem_core(core_name):
                params = subblock.get("parameters", {})
                memories.append(
                    {
                        "instance_name": subblock.get("instance_name", ""),
                        "type": core_name,
                        "addr_w": int(params.get("ADDR_W", 0)),
                        "data_w": int(params.get("DATA_W", 32)),
                        "parameters": params,
                    }
                )
            # Recurse into nested subblocks
            if "subblocks" in subblock:
                scan_subblocks(subblock["subblocks"])

    # Scan the top core's own subblocks (memories instantiated directly).
    if hasattr(core, "attributes_dict"):
        scan_subblocks(core.attributes_dict.get("subblocks", []))

    # Scan superblocks (e.g. the memory wrapper), which hold the memory
    # instances that were hoisted out of the top core's subblocks.
    for superblock in getattr(core, "superblocks", []):
        if hasattr(superblock, "attributes_dict"):
            scan_subblocks(superblock.attributes_dict.get("subblocks", []))

    # Deduplicate by instance_name
    seen = set()
    unique_memories = []
    for mem in memories:
        if mem["instance_name"] not in seen:
            seen.add(mem["instance_name"])
            unique_memories.append(mem)

    return unique_memories


def get_default_config(core, pdk="sky130A", clock_period=10, extra_config=None):
    """Build the default LibreLane configuration dictionary for a core.

    :param core: the iob_core object of the top module
    :param pdk: PDK variant to target (e.g. 'sky130A')
    :param clock_period: clock period (ns) of the main clock domain
    :param extra_config: dictionary merged into (and overriding) the result
    """
    # For iob_system with ASIC wrapper, use the ASIC wrapper as top module
    top_name = core.name
    verilog_dir = os.path.join(core.build_dir, "hardware", "src")
    if hasattr(core, "attributes_dict") and core.attributes_dict.get("is_system"):
        # Check if ASIC wrapper is enabled
        if core.received_python_parameters.get("asic_wrapper", False):
            top_name = f"{core.name}_asic"
            verilog_dir = os.path.join(core.build_dir, "hardware", "asic")

    verilog_path = os.path.join(verilog_dir, f"{top_name}.v")
    clock_ports = find_clock_ports(get_top_module_ports(verilog_path, top_name))
    vdd_nets, gnd_nets = get_pdk_power_nets(pdk)

    # Scan memories and map to macros
    memories = scan_memories(core)
    macros = []
    for mem in memories:
        macro_name, macro_addr_w, macro_data_w = map_memory_to_macro(
            mem["addr_w"], mem["data_w"]
        )
        macros.append(
            {
                "macro_name": mem["instance_name"],
                "lib_name": macro_name,
                "placement": "auto",
            }
        )

    config = {
        "DESIGN_NAME": top_name,
        "VERILOG_FILES": ["dir::../src/*.v", "dir::*.v"],
        "VERILOG_INCLUDE_DIRS": ["dir::../src", "dir::."],
        "PDK": pdk,
        "CLOCK_PORT": clock_ports if len(clock_ports) > 1 else clock_ports[0],
        "CLOCK_PERIOD": clock_period,
        "VDD_NETS": vdd_nets,
        "GND_NETS": gnd_nets,
        "PNR_SDC_FILE": "dir::impl.sdc",
        "SIGNOFF_SDC_FILE": "dir::signoff.sdc",
        "MAX_FANOUT_CONSTRAINT": DEFAULT_MAX_FANOUT,
        "IO_DELAY_CONSTRAINT": DEFAULT_IO_DELAY_CONSTRAINT,
        "FP_CORE_UTIL": DEFAULT_FP_CORE_UTIL,
        "PL_OPTIMIZE_MIRRORING": bool(int(DEFAULT_PL_OPTIMIZE_MIRRORING)),
        "TIMING_VIOLATION_CORNERS": DEFAULT_TIMING_VIOLATION_CORNERS,
        "LINTER_DISABLE_WARNINGS": DEFAULT_LINTER_DISABLE_WARNINGS,
    }
    if macros:
        config["MACRO"] = macros
    # Note: sky130 SRAM macros are part of the PDK and auto-detected from Verilog instantiations
    # But we specify them in config for explicit placement control
    config.update(extra_config or {})
    return config


def write_config(config, asic_dir):
    """Write the LibreLane configuration file to the ASIC directory of a build dir"""
    os.makedirs(asic_dir, exist_ok=True)
    config_path = os.path.join(asic_dir, "config.json")
    with open(config_path, "w") as f:
        json.dump(config, f, indent=4)
        f.write("\n")
    return config_path


def asic_config_gen(core, pdk="sky130A", clock_period=10, extra_config=None):
    """Generate the ASIC (LibreLane) configuration file of a core's build dir.

    :param core: the iob_core object of the top module
    :param pdk: PDK variant to target (e.g. 'sky130A')
    :param clock_period: clock period (ns) of the main clock domain
    :param extra_config: dictionary merged into (and overriding) the defaults
    :return: path of the generated configuration file
    """
    asic_dir = os.path.join(core.build_dir, "hardware", "asic")
    try:
        config = get_default_config(core, pdk, clock_period, extra_config)
    except (ValueError, FileNotFoundError) as e:
        print(f"{WARNING} ASIC flow configuration not generated: {e}{ENDC}")
        return None
    config_path = write_config(config, asic_dir)
    print(f"{OK} ASIC flow configuration written to '{config_path}'.{ENDC}")
    return config_path
