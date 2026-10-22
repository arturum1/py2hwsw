#!/usr/bin/env python3

# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: GPL-3.0-only

"""Generate the LibreLane configuration file for the ASIC flow.

The LibreLane configuration (JSON) is written to
'<build_dir>/hardware/asic/config.json' and describes the design to the flow:
its name, its Verilog sources, its clock, and the technology to use.
"""

import glob
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


# Sky130 SRAM macros available in the PDK, with their geometry.
# The address and data widths of the ports of a macro are fixed, so a macro
# can only implement a memory with exactly the same geometry. Keep this table
# in sync with the macro selection of 'sram_1rw1r_wrapper.v'.
SKY130_MACROS = {
    # 1RW+1R macros - 32-bit data width
    "sky130_sram_1kbyte_1rw1r_32x256_8": {"addr_width": 8, "data_width": 32},
    "sky130_sram_2kbyte_1rw1r_32x512_8": {"addr_width": 9, "data_width": 32},
    # 1RW+1R macros - 8-bit data width
    "sky130_sram_1kbyte_1rw1r_8x1024_8": {"addr_width": 10, "data_width": 8},
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


def find_macro(addr_w, data_w):
    """Return the name of the sky130 macro with exactly this geometry.

    Returns None if the PDK has no macro with the requested geometry, in which
    case the memory is implemented with standard cells.
    """
    for name, geometry in SKY130_MACROS.items():
        if geometry["addr_width"] == addr_w and geometry["data_width"] == data_w:
            return name
    return None


def get_pdk_macros_dir(pdk):
    """Return the directory with the views of the SRAM macros of a PDK variant.

    Returns None if the PDK does not provide any SRAM macro.
    """
    candidates = []
    if pdk_root := os.environ.get("PDK_ROOT"):
        candidates.append(
            os.path.join(pdk_root, pdk, "libs.ref", "sky130_sram_macros")
        )
    candidates.append(
        os.path.join(
            os.path.expanduser("~"), ".ciel", pdk, "libs.ref", "sky130_sram_macros"
        )
    )
    for candidate in candidates:
        if os.path.isdir(candidate):
            return candidate
    return None


def get_macro_views(macros_dir, macro_name):
    """Return the views of a macro: GDSII, LEF, Verilog model and Liberty.

    The Verilog model is needed by the synthesis flow to resolve the
    instantiation of the macro in the RTL, and the Liberty file by the static
    timing analysis.
    """
    views = {"gds": [], "lef": [], "vh": [], "lib": {}}

    gds = os.path.join(macros_dir, "gds", f"{macro_name}.gds")
    lef = os.path.join(macros_dir, "lef", f"{macro_name}.lef")
    vh = os.path.join(macros_dir, "verilog", f"{macro_name}.v")
    if os.path.isfile(gds):
        views["gds"].append(gds)
    if os.path.isfile(lef):
        views["lef"].append(lef)
    if os.path.isfile(vh):
        views["vh"].append(vh)

    libs = sorted(
        glob.glob(os.path.join(macros_dir, "lib", f"{macro_name}_*.lib"))
    )
    if libs:
        views["lib"] = {"*": libs}

    return views


def get_macros_config(memories, pdk):
    """Return the 'MACROS' configuration of the memories of a design.

    Only the memories whose geometry matches the geometry of a macro of the
    PDK are mapped to that macro. The other memories are implemented with
    standard cells, which is not an error: it only makes the design bigger.
    """
    macros = {}

    if not memories:
        return macros

    macros_dir = get_pdk_macros_dir(pdk)
    if macros_dir is None:
        print(
            f"{WARNING} The SRAM macros of the PDK '{pdk}' were not found. "
            f"The memories of the design will be implemented with standard "
            f"cells.{ENDC}"
        )
        return macros

    for mem in memories:
        if not mem["type"].startswith("iob_ram_"):
            # The ROMs are always implemented with the behavioral model, so
            # they never instantiate a hard macro
            continue
        macro_name = find_macro(mem["addr_w"], mem["data_w"])
        if macro_name is None:
            print(
                f"{WARNING} The PDK has no SRAM macro with the geometry of the "
                f"memory '{mem['instance_name']}' ({mem['addr_w']}x{mem['data_w']}). "
                f"It will be implemented with standard cells.{ENDC}"
            )
            continue
        if macro_name in macros:
            continue
        views = get_macro_views(macros_dir, macro_name)
        if not views["gds"] or not views["lef"]:
            print(
                f"{WARNING} The views of the SRAM macro '{macro_name}' are "
                f"incomplete in '{macros_dir}'. The memory "
                f"'{mem['instance_name']}' will be implemented with standard "
                f"cells.{ENDC}"
            )
            continue
        macros[macro_name] = views

    return macros


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

    # Scan memories and map them to the SRAM macros of the PDK
    memories = scan_memories(core)
    # The memories are only mapped to hard macros in the designs that
    # instantiate them, which are the ones built with the ASIC wrapper
    macros = get_macros_config(memories, pdk) if top_name.endswith("_asic") else {}

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
        # The Verilator lint step of the flow is only enabled for the cores
        # that pass the lint checks of the setup. The other cores have
        # warnings that would abort the flow.
        "RUN_LINTER": bool(getattr(core, "global_project_vlint", True)),
    }
    if macros:
        config["MACROS"] = macros
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
