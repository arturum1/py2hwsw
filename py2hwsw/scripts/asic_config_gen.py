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


def get_default_config(core, pdk="sky130A", clock_period=10, extra_config=None):
    """Build the default LibreLane configuration dictionary for a core.

    :param core: the iob_core object of the top module
    :param pdk: PDK variant to target (e.g. 'sky130A')
    :param clock_period: clock period (ns) of the main clock domain
    :param extra_config: dictionary merged into (and overriding) the result
    """
    verilog_path = os.path.join(core.build_dir, "hardware", "src", f"{core.name}.v")
    clock_ports = find_clock_ports(get_top_module_ports(verilog_path, core.name))
    vdd_nets, gnd_nets = get_pdk_power_nets(pdk)

    config = {
        "DESIGN_NAME": core.name,
        "VERILOG_FILES": ["dir::../src/*.v"],
        "VERILOG_INCLUDE_DIRS": ["dir::../src"],
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
