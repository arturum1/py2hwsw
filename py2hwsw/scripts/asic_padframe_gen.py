#!/usr/bin/env python3

# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: GPL-3.0-only

"""Generate a Sky130 pad-ring wrapper and its LibreLane Chip configuration."""

import copy
import json
import math
import os
import re
import subprocess

PAD_CELL = "sky130_ef_io__gpiov2_pad"
PAD_SIDE_NAMES = ("PAD_SOUTH", "PAD_EAST", "PAD_NORTH", "PAD_WEST")
PAD_SITE_WIDTH = 80
PAD_CORNER_SIZE = 200
CORE_MARGIN = 400

POWER_PADS = {
    "vccd": {
        "cell": "sky130_ef_io__vccd_lvc_clamped_pad",
        "pad_pin": "VCCD_PAD",
        "core_pin": "VCCD",
        "net": "VPWR",
        "width": 75,
    },
    "vssd": {
        "cell": "sky130_ef_io__vssd_lvc_clamped_pad",
        "pad_pin": "VSSD_PAD",
        "core_pin": "VSSD",
        "net": "VGND",
        "width": 75,
    },
    "vddio": {
        "cell": "sky130_ef_io__vddio_hvc_clamped_pad",
        "pad_pin": "VDDIO_PAD",
        "core_pin": "VDDIO",
        "net": "vddio",
        "width": 75,
    },
    "vssio": {
        "cell": "sky130_ef_io__vssio_hvc_clamped_pad",
        "pad_pin": "VSSIO_PAD",
        "core_pin": "VSSIO",
        "net": "vssio",
        "width": 75,
    },
    "vdda": {
        "cell": "sky130_ef_io__vdda_hvc_clamped_pad",
        "pad_pin": "VDDA_PAD",
        "core_pin": "VDDA",
        "net": "vdda",
        "width": 75,
    },
    "vssa": {
        "cell": "sky130_ef_io__vssa_hvc_clamped_pad",
        "pad_pin": "VSSA_PAD",
        "core_pin": "VSSA",
        "net": "vssa",
        "width": 75,
    },
}

COMMON_SUPPLIES = {
    "AMUXBUS_A": "amuxbus_a",
    "AMUXBUS_B": "amuxbus_b",
    "VSSA": "vssa",
    "VDDA": "vdda",
    "VSWITCH": "vddio",
    "VDDIO_Q": "vddio",
    "VCCHIB": "VPWR",
    "VDDIO": "vddio",
    "VCCD": "VPWR",
    "VSSIO": "vssio",
    "VSSD": "VGND",
    "VSSIO_Q": "vssio",
}


def find_matching_paren(text, start):
    depth = 0
    for index in range(start, len(text)):
        if text[index] == "(":
            depth += 1
        elif text[index] == ")":
            depth -= 1
            if depth == 0:
                return index
    return -1


def split_declarations(text):
    declarations = []
    start = 0
    depth = 0
    for index, char in enumerate(text):
        if char in "[(":
            depth += 1
        elif char in "])":
            depth -= 1
        elif char == "," and depth == 0:
            declarations.append(text[start:index])
            start = index + 1
    declarations.append(text[start:])
    return declarations


def get_module_info(verilog_path, module_name):
    with open(verilog_path) as file:
        content = file.read()
    match = re.search(rf"\bmodule\s+{re.escape(module_name)}\b", content)
    if not match:
        raise ValueError(f"Module '{module_name}' not found in '{verilog_path}'")

    header_end = content.find(");", match.start())
    if header_end == -1:
        raise ValueError(f"Malformed header of module '{module_name}'")
    header_end += 1
    header = content[match.start() : header_end]
    header = re.sub(r"//.*", "", header)

    after_name = content[match.end() : header_end]
    if re.match(r"\s*#\s*\(", after_name):
        param_open = content.find("(", match.end())
        param_close = find_matching_paren(content, param_open)
        if param_close == -1:
            raise ValueError(f"Malformed parameter list of module '{module_name}'")
        params_raw = re.sub(r"//.*", "", content[param_open + 1 : param_close]).strip()
        port_open = content.find("(", param_close + 1)
    else:
        params_raw = ""
        port_open = content.find("(", match.end())
    port_close = find_matching_paren(content, port_open)
    if port_close == -1:
        raise ValueError(f"Malformed port list of module '{module_name}'")

    ports = []
    port_text = re.sub(r"//.*", "", content[port_open + 1 : port_close])
    for declaration in split_declarations(port_text):
        match_port = re.match(
            r"^\s*(input|output|inout)\s*(?:(?:wire|reg|logic)\s+)?(\[[^\]]*\])?\s*([A-Za-z_]\w*)\s*$",
            declaration,
            flags=re.DOTALL,
        )
        if match_port:
            direction, width, name = match_port.groups()
            ports.append(
                {
                    "name": name,
                    "direction": direction,
                    "width": re.sub(r"\s+", " ", width.strip()) if width else "",
                }
            )

    includes = re.findall(r'`include\s+"([^"]+)"', content[: match.start()])
    return includes, params_raw, ports


def get_macros(verilog_dir, includes):
    macros = {}
    for include in includes:
        include_path = os.path.join(verilog_dir, include)
        if not os.path.isfile(include_path):
            continue
        with open(include_path) as file:
            content = file.read()
        for match in re.finditer(r"`define\s+(\w+)(?:\s+([^\n]*))?", content):
            value = re.sub(r"//.*", "", match.group(2) or "1").strip()
            macros[match.group(1)] = value
    return macros


def get_parameters(params_raw, macros):
    parameters = {}
    for match in re.finditer(
        r"\bparameter\s+([A-Za-z_]\w*)\s*=\s*([^,)]+)", params_raw, flags=re.DOTALL
    ):
        parameters[match.group(1)] = match.group(2).strip()
    resolved = {}
    for _ in range(len(parameters) + 1):
        for name, expression in parameters.items():
            if name in resolved:
                continue
            value = evaluate_expression(expression, macros, resolved)
            if value is not None:
                resolved[name] = value
    return list(parameters), resolved


def evaluate_expression(expression, macros, parameters):
    value = expression.strip()
    for _ in range(10):
        previous = value
        value = re.sub(
            r"`([A-Za-z_]\w*)",
            lambda match: str(macros.get(match.group(1), match.group(0))),
            value,
        )
        for name, parameter_value in parameters.items():
            value = re.sub(rf"\b{re.escape(name)}\b", str(parameter_value), value)
        if value == previous:
            break
    value = value.replace(" ", "")
    if not re.fullmatch(r"[0-9+\-*/()%]+", value):
        return None
    try:
        return int(eval(value, {"__builtins__": {}}, {}))
    except (ArithmeticError, SyntaxError):
        return None


def get_port_range(port, macros, parameters):
    if not port["width"]:
        return 0, 0
    match = re.match(r"\[\s*(.+)\s*:\s*(.+)\s*\]", port["width"])
    if not match:
        return None, None
    high = evaluate_expression(match.group(1), macros, parameters)
    low = evaluate_expression(match.group(2), macros, parameters)
    return high, low


def get_port_width(port, macros, parameters):
    high, low = get_port_range(port, macros, parameters)
    if high is None or low is None:
        return None
    return high - low + 1


def _get_port_low_bit(port, macros, parameters):
    _, low = get_port_range(port, macros, parameters)
    return low or 0


def unique_name(base, used):
    name = base
    while name in used:
        name += "_pad"
    used.add(name)
    return name


def common_supply_connections(exclude=()):
    return [(pin, net) for pin, net in COMMON_SUPPLIES.items() if pin not in exclude]


def pad_connections(pin, net):
    return f".{pin}({net})" if net is not None else f".{pin}()"


def die_side_for_pads(pads, gap_sites):
    total_width = sum(pad["width"] for pad in pads)
    side = (
        2 * PAD_CORNER_SIZE + total_width + gap_sites * PAD_SITE_WIDTH * (len(pads) + 1)
    )
    if not pads:
        return 2 * PAD_CORNER_SIZE + 2 * PAD_SITE_WIDTH
    for _ in range(10000):
        fill = side - 2 * PAD_CORNER_SIZE - total_width
        gap = math.floor(fill / (len(pads) + 1) / PAD_SITE_WIDTH) * PAD_SITE_WIDTH
        remainder = (fill - gap * (len(pads) - 1)) / 2
        rounded = round(remainder / PAD_SITE_WIDTH) * PAD_SITE_WIDTH
        if remainder >= 0 and abs(remainder - rounded) < 1e-6:
            return int(round(side))
        side += PAD_SITE_WIDTH
    raise ValueError("Could not compute a pad-ring-compliant die area")


def asic_padframe_gen(core, config, pdk="sky130A"):
    if not pdk.startswith("sky130"):
        print(f"Padframe generation is not supported for PDK '{pdk}'.")
        return None

    asic_dir = os.path.join(core.build_dir, "hardware", "asic")
    top_name = config["DESIGN_NAME"]
    if top_name.endswith("_asic"):
        verilog_dir = asic_dir
    else:
        verilog_dir = os.path.join(core.build_dir, "hardware", "src")
    verilog_path = os.path.join(verilog_dir, f"{top_name}.v")
    if not os.path.isfile(verilog_path):
        print(f"Padframe generation skipped: '{verilog_path}' not found.")
        return None

    includes, params_raw, ports = get_module_info(verilog_path, top_name)
    macros = get_macros(verilog_dir, includes)
    param_names, parameters = get_parameters(params_raw, macros)
    for port in ports:
        width = get_port_width(port, macros, parameters)
        if width is None or width < 1:
            print(
                f"Padframe generation skipped: cannot resolve width of port "
                f"'{port['name']}'."
            )
            return None
        port["bit_width"] = width
        port["low_bit"] = _get_port_low_bit(port, macros, parameters)

    wrapper_name = f"{top_name}_pads"
    used_names = {port["name"] for port in ports}
    used_names.add(wrapper_name)

    core_nets = {}
    for port in ports:
        core_nets[port["name"]] = unique_name(port["name"] + "_core", used_names)

    power_ports = {}
    for name in POWER_PADS:
        power_ports[name] = unique_name(f"{name}_pad", used_names)

    supply_nets = ["VPWR", "VGND", "vddio", "vssio", "vdda", "vssa"]
    for net in supply_nets:
        if net in used_names:
            print(f"Padframe generation skipped: supply net '{net}' is already used.")
            return None
        used_names.add(net)
    for net in ("amuxbus_a", "amuxbus_b"):
        if net in used_names:
            print(f"Padframe generation skipped: net '{net}' is already used.")
            return None
        used_names.add(net)

    signal_pads = []
    for port in ports:
        base = unique_name("pad_" + port["name"], used_names)
        for bit in range(port["bit_width"]):
            instance = base if port["bit_width"] == 1 else f"{base}_{bit}"
            bit_index = port["low_bit"] + bit
            pad_net = (
                port["name"]
                if port["bit_width"] == 1
                else f"{port['name']}[{bit_index}]"
            )
            core_net = (
                core_nets[port["name"]]
                if port["bit_width"] == 1
                else f"{core_nets[port['name']]}[{bit_index}]"
            )
            signal_pads.append(
                {
                    "instance": instance,
                    "cell": PAD_CELL,
                    "width": PAD_SITE_WIDTH,
                    "pad_net": pad_net,
                    "core_net": core_net,
                    "direction": port["direction"],
                }
            )

    power_pad_list = []
    for name, spec in POWER_PADS.items():
        power_pad_list.append(
            {
                "instance": unique_name("pad_" + name, used_names),
                "cell": spec["cell"],
                "width": spec["width"],
                "spec": spec,
                "pad_net": power_ports[name],
            }
        )

    side_pads = [list(group) for group in _split_pads(signal_pads, 4)]
    for index, pad in enumerate(power_pad_list):
        side_pads[index % len(PAD_SIDE_NAMES)].append(pad)

    gap_sites = int(os.environ.get("ASIC_PAD_GAP", 2))
    horizontal_count = [side_pads[0], side_pads[2]]
    vertical_count = [side_pads[1], side_pads[3]]
    die_width = max(die_side_for_pads(pads, gap_sites) for pads in horizontal_count)
    die_height = max(die_side_for_pads(pads, gap_sites) for pads in vertical_count)
    if die_width <= 2 * CORE_MARGIN or die_height <= 2 * CORE_MARGIN:
        print("Padframe generation skipped: die area is too small for the core.")
        return None

    if "ASIC_DIE_AREA" in os.environ:
        die_area = [
            int(value.strip()) for value in os.environ["ASIC_DIE_AREA"].split(",")
        ]
    else:
        die_area = [0, 0, die_width, die_height]
    if "ASIC_CORE_AREA" in os.environ:
        core_area = [
            int(value.strip()) for value in os.environ["ASIC_CORE_AREA"].split(",")
        ]
    else:
        core_area = [
            CORE_MARGIN,
            CORE_MARGIN,
            die_area[2] - CORE_MARGIN,
            die_area[3] - CORE_MARGIN,
        ]

    lines = [
        # REUSE-IgnoreStart
        "// SPDX-FileCopyrightText: 2026 IObundle",
        "//",
        "// SPDX-License-Identifier: GPL-3.0-only",
        "//",
        # REUSE-IgnoreEnd
        "`timescale 1ns / 1ps",
    ]
    lines.extend(f'`include "{include}"' for include in includes)
    lines.append("")
    if params_raw:
        lines.append(f"module {wrapper_name} #(")
        lines.extend(f"   {line.strip()}" for line in params_raw.splitlines())
        lines.append(") (")
    else:
        lines.append(f"module {wrapper_name} (")

    for port in ports:
        width = f" {port['width']}" if port["width"] else ""
        lines.append(f"   inout{width} {port['name']},")
    for name, port_name in power_ports.items():
        suffix = "" if name == list(power_ports)[-1] else ","
        lines.append(f"   inout {port_name}{suffix}")
    lines.append(");")
    lines.append("")

    for net in supply_nets + ["amuxbus_a", "amuxbus_b"]:
        lines.append(f"   wire {net};")
    for port in ports:
        width = f" {port['width']}" if port["width"] else ""
        lines.append(f"   wire{width} {core_nets[port['name']]};")
    lines.append("")

    if param_names:
        lines.append(f"   {top_name} #(")
        for index, name in enumerate(param_names):
            comma = "" if index == len(param_names) - 1 else ","
            lines.append(f"      .{name}({name}){comma}")
        lines.append("   ) core_inst (")
    else:
        lines.append(f"   {top_name} core_inst (")
    for index, port in enumerate(ports):
        comma = "" if index == len(ports) - 1 else ","
        lines.append(f"      .{port['name']}({core_nets[port['name']]}){comma}")
    lines.append("   );")
    lines.append("")

    for pad in power_pad_list:
        spec = pad["spec"]
        connections = common_supply_connections(exclude=(spec["core_pin"],))
        connections.extend(
            [(spec["pad_pin"], pad["pad_net"]), (spec["core_pin"], spec["net"])]
        )
        lines.append(f"   {spec['cell']} {pad['instance']} (")
        for pin, net in connections:
            lines.append(f"      {pad_connections(pin, net)},")
        lines[-1] = lines[-1][:-1]
        lines.append("   );")
        lines.append("")

    for pad in signal_pads:
        output_mode = pad["direction"] == "output"
        connections = common_supply_connections()
        connections.extend(
            [
                ("PAD", pad["pad_net"]),
                ("IN", None if output_mode else pad["core_net"]),
                ("OUT", pad["core_net"] if output_mode else "1'b0"),
                ("OE_N", "1'b0" if output_mode else "1'b1"),
                ("DM", "3'b110" if output_mode else "3'b001"),
                ("INP_DIS", "1'b1" if output_mode else "1'b0"),
                ("HLD_H_N", "1'b1"),
                ("ENABLE_H", "1'b1"),
                ("ENABLE_INP_H", "1'b0"),
                ("ENABLE_VDDA_H", "1'b1"),
                ("ENABLE_VSWITCH_H", "1'b0"),
                ("ENABLE_VDDIO", "1'b1"),
                ("IB_MODE_SEL", "1'b0"),
                ("VTRIP_SEL", "1'b0"),
                ("SLOW", "1'b0"),
                ("HLD_OVR", "1'b0"),
                ("ANALOG_EN", "1'b0"),
                ("ANALOG_SEL", "1'b0"),
                ("ANALOG_POL", "1'b0"),
                ("PAD_A_NOESD_H", None),
                ("PAD_A_ESD_0_H", None),
                ("PAD_A_ESD_1_H", None),
                ("IN_H", None),
                ("TIE_HI_ESD", None),
                ("TIE_LO_ESD", None),
            ]
        )
        lines.append(f"   {PAD_CELL} {pad['instance']} (")
        for pin, net in connections:
            lines.append(f"      {pad_connections(pin, net)},")
        lines[-1] = lines[-1][:-1]
        lines.append("   );")
        lines.append("")

    lines.append("endmodule")
    lines.append("")
    wrapper_path = os.path.join(asic_dir, f"{wrapper_name}.v")
    with open(wrapper_path, "w") as file:
        file.write("\n".join(lines))
    try:
        subprocess.run(
            ["verible-verilog-format", "--inplace", wrapper_path],
            check=True,
            stdout=subprocess.DEVNULL,
        )
    except (FileNotFoundError, subprocess.CalledProcessError):
        pass

    pad_config = copy.deepcopy(config)
    pad_config["DESIGN_NAME"] = wrapper_name
    pad_config["IO_DELAY_CONSTRAINT"] = 20
    pad_config["PAD_CELL_LIBRARY"] = "sky130_ef_io"
    pad_config["FP_SIZING"] = "absolute"
    pad_config["DIE_AREA"] = die_area
    pad_config["CORE_AREA"] = core_area
    pad_config["RUN_LINTER"] = False
    pad_config["PAD_LIBS"] = None
    for name, pads in zip(PAD_SIDE_NAMES, side_pads):
        pad_config[name] = [pad["instance"] for pad in pads]

    pad_config_path = os.path.join(asic_dir, "config_padframe.json")
    with open(pad_config_path, "w") as file:
        json.dump(pad_config, file, indent=4)
        file.write("\n")
    print(f"Padframe configuration written to '{pad_config_path}'.")
    return pad_config_path


def _split_pads(pads, groups):
    result = [[] for _ in range(groups)]
    per_group = math.ceil(len(pads) / groups) if pads else 0
    for index, pad in enumerate(pads):
        result[min(index // per_group, groups - 1) if per_group else groups - 1].append(
            pad
        )
    return result
