# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: GPL-3.0-only

import copy
import os
import sys
from latex import write_table
from iob_base import find_obj_in_list, import_python_module
from iob_core import find_module_setup_dir


def get_conf_names(confs):
    """Return the list of conf names, flattening conf groups.

    :param list confs: List of conf dicts (may contain groups with a nested
        "confs" key).
    :return: List of conf name strings.
    """
    names = []
    for conf in confs:
        if "confs" in conf:
            names += get_conf_names(conf["confs"])
        else:
            names.append(conf["name"])
    return names


def setup(py_params_dict):
    """Memory wrapper core. Inteended to be used as a superblock of other cores.
    Required memories are automatically generated based on the ports of the issuer (subblock).
    """
    # Check if should create a demonstation of this core
    if py_params_dict.get("demo", False):
        py_params_dict["mem_if_names"] = []
        py_params_dict["issuer"] = {
            "original_name": "iob_core",
            "name": "iob",
            "confs": [],
            "ports": [],
        }

    # Get issuer - either from py_params_dict["issuer"] (full dict) or by name from py_params_dict["issuer_name"]
    issuer = py_params_dict.get("issuer")
    if issuer is None:
        issuer_name = py_params_dict.get("issuer_name")
        if issuer_name:
            # Dynamically import and setup the issuer
            import_python_module(
                os.path.join(find_module_setup_dir(issuer_name), f"{issuer_name}.py")
            )
            issuer_module = sys.modules[issuer_name]
            # Pass relevant py_params to issuer setup
            issuer_py_params = {
                k: v
                for k, v in py_params_dict.items()
                if k
                in [
                    "py2hwsw_version",
                    "build_dir",
                    "py2hwsw_target",
                    "iob_system_params",
                    "asic_wrapper",
                ]
            }
            issuer = issuer_module.setup(
                {
                    "iob_system_params": issuer_py_params.get("iob_system_params", {}),
                    "py2hwsw_version": issuer_py_params.get(
                        "py2hwsw_version", "0.81.0"
                    ),
                    "build_dir": issuer_py_params.get("build_dir", ""),
                    "py2hwsw_target": issuer_py_params.get("py2hwsw_target", "setup"),
                }
            )
        else:
            # Demo mode fallback
            py_params_dict["mem_if_names"] = []
            py_params_dict["issuer"] = {
                "original_name": "iob_core",
                "name": "iob",
                "confs": [],
                "ports": [],
            }
            issuer = py_params_dict["issuer"]

    attrs = issuer

    # Determine memory interface names from issuer's ports if not provided
    mem_if_names = py_params_dict.get("mem_if_names", [])
    if not mem_if_names:
        # Auto-detect memory interfaces from issuer's ports
        for port in attrs.get("ports", []):
            if isinstance(port["signals"], dict) and "type" in port["signals"]:
                if port["signals"]["type"] in ["rom_sp", "ram_t2p", "ram_t2p_be"]:
                    mem_if_names.append(port["signals"]["type"])

    attributes_dict = {
        "name": f"{attrs['name']}_mwrap",
        "generate_hw": True,
        "confs": attrs["confs"],
    }

    mwrap_wires = []
    mwrap_ports = []
    memory_ports = []
    for port in attrs["ports"]:
        if isinstance(port["signals"], dict):
            if port["signals"]["type"] in mem_if_names:
                wire = copy.deepcopy(port)
                wire["name"] = wire["name"][:-2]
                mwrap_wires.append(wire)
                memory_ports.append(port)
            else:
                mwrap_ports.append(port)
        else:
            mwrap_ports.append(port)

    attributes_dict["ports"] = mwrap_ports

    attributes_dict["wires"] = mwrap_wires

    connect_dict = {
        p["name"]: w["name"]
        for p, w in zip(memory_ports + mwrap_ports, mwrap_wires + mwrap_ports)
    }

    confs_without_groups = []
    for item in attrs["confs"]:
        if "confs" in item:
            # item is a group of confs
            confs_without_groups += item["confs"]
        else:
            # item is a single conf
            confs_without_groups.append(item)

    attributes_dict["subblocks"] = [
        {
            "core": attrs["original_name"],
            "instance_name": f"{attrs['name']}_inst",
            "instance_description": "Wrapped module",
            "parameters": {
                i["name"]: i["name"]
                for i in confs_without_groups
                if i["type"] in ["P", "D"] and not isinstance(i["val"], (dict, list))
            }
            | {
                k: v
                for k, v in py_params_dict.items()
                if k
                in [
                    "MEM_ASIC",
                    "MEM_NO_READ_ON_WRITE",
                ]
            },
            "connect": connect_dict,
        }
    ]

    list_of_mems = []
    for wire in mwrap_wires:
        if wire["signals"].get("prefix", None):
            prefix_str = wire["signals"]["prefix"]
        else:
            prefix_str = wire["name"] + "_"

        signals_type = wire["signals"]["type"]

        # Instance name
        name = f"{prefix_str}mem"
        # Memory type
        type = f"iob_{signals_type}"
        # Data bus width
        data_w = wire["signals"].get("DATA_W", 32)
        # Address bus width
        word_addr_w = wire["signals"].get("ADDR_W", 32)
        # Memory init hexfile name
        hexfile_param = f"{prefix_str.upper()}HEXFILE"
        hexfile_obj = find_obj_in_list(confs_without_groups, hexfile_param)
        if hexfile_obj is None:
            hexfile = "none"
            hexfile_param = '"none"'
        else:
            hexfile = hexfile_obj["val"]

        # Add memory instance to list
        list_of_mems.append(
            {
                "name": name,
                "type": type,
                "addr_w": word_addr_w,
                "data_w": data_w,
                "hexfile": hexfile,
            }
        )

        # Extra Verilog parameters for this memory subblock.
        # Forward MEM_ASIC (and MEM_NO_READ_ON_WRITE for RAMs) from the wrapper
        # confs so the memory follows the wrapper's configuration. The memory
        # primitives select behavioral RTL vs ASIC hard macros with MEM_ASIC
        # alone, so SIMULATION is not forwarded to them.
        extra_params = {}
        if "ram" in type or "rom" in type:
            mem_dir, file_ext = find_module_setup_dir(type)
            import_python_module(os.path.join(mem_dir, f"{type}.py"))
            mem_module = sys.modules[type]
            mem_dict = mem_module.setup({})
            mem_conf_names = get_conf_names(mem_dict.get("confs", []))
            if "MEM_ASIC" in mem_conf_names:
                extra_params["MEM_ASIC"] = "MEM_ASIC"
            if "MEM_NO_READ_ON_WRITE" in mem_conf_names:
                extra_params["MEM_NO_READ_ON_WRITE"] = "MEM_NO_READ_ON_WRITE"

        # Add memory instace to subblocks list
        attributes_dict["subblocks"].append(
            {
                "core": type,
                "instance_name": name,
                "parameters": {
                    "DATA_W": data_w,
                    "ADDR_W": word_addr_w,
                    "HEXFILE": hexfile_param,
                }
                | extra_params,
                "connect": {
                    f"{signals_type}_s": wire["name"],
                },
            }
        )

    if "superblocks" in attrs:
        attributes_dict["superblocks"] = attrs["superblocks"]

    # Add MEM_NO_READ_ON_WRITE to the attributes dictionary
    # if the user has not set it
    has_mem_no_read_on_write_in_attrs = False
    for conf in confs_without_groups:
        if conf["name"] == "MEM_NO_READ_ON_WRITE":
            has_mem_no_read_on_write_in_attrs = True
            break
    if not has_mem_no_read_on_write_in_attrs:
        attributes_dict["confs"] += [
            {
                "name": "MEM_NO_READ_ON_WRITE",
                "type": "P",
                "val": "0",
                "min": "0",
                "max": "1",
                "descr": "No simultaneous read/write",
            },
        ]

    # Add MEM_ASIC to the attributes dictionary
    # if the user has not set it
    has_mem_asic_in_attrs = False
    for conf in confs_without_groups:
        if conf["name"] == "MEM_ASIC":
            has_mem_asic_in_attrs = True
            break
    if not has_mem_asic_in_attrs:
        attributes_dict["confs"] += [
            {
                "name": "MEM_ASIC",
                "type": "P",
                "val": "0",
                "min": "0",
                "max": "1",
                "descr": "Use ASIC hard macros (1) or behavioral RTL (0)",
            },
        ]

    # Generate LaTeX table of memories
    # But don't create files for other targets (like clean)
    if py_params_dict.get("py2hwsw_target", "") == "setup":
        assert py_params_dict["build_dir"], "[iob_memwrapper]: Error: build_dir not set"
        generate_mems_tex(
            list_of_mems, os.path.join(py_params_dict["build_dir"], "document/tsrc")
        )

    return attributes_dict


#
# Document functions
#


# Generate mems.tex file with list TeX tables of mems
def generate_mems_tex(mems, out_dir):
    """Generate TeX for memories section
    :param mems: list of memories
    :param out_dir: output directory
    """
    os.makedirs(out_dir, exist_ok=True)
    mems_file = open(f"{out_dir}/mems.tex", "w")

    mems_file.write(
        """
    The memories of the core are described in the following table.
    The tables give information on the name, type, address and data width in bits, and initialization file name.
"""
    )

    mems_file.write(
        """
    {
    \\setlength{\\LTcapwidth}{\\linewidth} % make sure the caption takes up the whole linewidth
    \\begin{xltabular}{\\textwidth}{|l|c|c|c|X|}
      \\hline
      \\rowcolor{iob-green}
      {\\bf Name} & {\\bf Type} & {\\bf (Word-)Addr Width} & {\\bf Data Width} & {\\bf Init file} \\\\ \\hline
      \\endfirsthead
      \\hline
      \\caption{Core memories.}
      \\endlastfoot
      \\input mems_tab
    \\end{xltabular}
    \\label{mems_tab:is}
}
"""
    )

    mems_file.write("\\clearpage")
    mems_file.close()

    # Generate mems table
    tex_table = []
    for mem in mems:
        tex_table.append(
            [
                mem["name"],
                mem["type"],
                str(mem["addr_w"]),
                str(mem["data_w"]),
                mem["hexfile"],
            ]
        )

    write_table(f"{out_dir}/mems", tex_table)
