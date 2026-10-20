# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: GPL-3.0-only

import copy


def setup(py_params_dict):
    """ASIC top wrapper for iob_system.

    This follows the same pattern as the simulation and FPGA wrappers: it is a
    superblock of the iob_system memory wrapper (iob_system_mwrap). The memory
    wrapper is shared by every flow (sim/fpga/asic); only the top changes. This
    ASIC top forces the use of ASIC hard macros by passing MEM_ASIC=1 (and
    MEM_NO_READ_ON_WRITE=1) to the memory wrapper, which forwards them to the
    instantiated memory primitives. No Verilog define is required.
    """
    # The issuer is the iob_system memory wrapper. Its external (non-memory)
    # ports become the ports of this ASIC top and are connected 1:1 to the
    # wrapped memory wrapper instance.
    issuer = py_params_dict.get("issuer", {})
    ports = copy.deepcopy(issuer.get("ports", []))
    connect = {port["name"]: port["name"] for port in ports}

    attributes_dict = {
        "name": py_params_dict["iob_system_params"]["name"] + "_asic",
        "generate_hw": True,
        "ports": ports,
        "subblocks": [
            {
                "core": issuer["original_name"],
                "instance_name": "iob_system_mwrap",
                "instance_description": "Memory wrapper (ASIC hard macros)",
                "parameters": {
                    "MEM_ASIC": 1,
                    "MEM_NO_READ_ON_WRITE": 1,
                },
                "connect": connect,
            },
        ],
    }

    return attributes_dict
