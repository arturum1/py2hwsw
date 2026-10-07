# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: GPL-3.0-only

import os
import copy
import sys
import json

from iob_colors import INFO, ENDC
from iob_base import find_obj_in_list, import_python_module
from iob_core import find_module_setup_dir


def setup(py_params_dict):
    """ASIC top wrapper for iob_system.

    This wrapper uses iob_memwrapper to wrap iob_system with MEM_ASIC=1
    for sky130 hard macro usage in memory modules.
    """
    # Get iob_system parameters
    params = py_params_dict.get("iob_system_params", {})

    # Add asic_wrapper to params so iob_system knows to use ASIC mode
    params = copy.deepcopy(params)
    params["asic_wrapper"] = py_params_dict.get("asic_wrapper", False)

    # Determine memory interface names based on iob_system config
    mem_if_names = []
    if params.get("use_bootrom", True):
        mem_if_names.append("rom_sp")
    if params.get("use_intmem", True):
        mem_if_names.append("ram_t2p_be")
    if params.get("use_extmem", False):
        mem_if_names.append("ram_t2p_be")

    # Get iob_system attributes (the issuer)
    iob_system_setup_dir = os.path.join(
        os.path.dirname(__file__), "..", "..", "..", "..", "iob_system"
    )
    sys.path.insert(0, iob_system_setup_dir)
    import iob_system

    iob_system_attrs = iob_system.setup(
        {
            "iob_system_params": params,
            "py2hwsw_version": py_params_dict.get("py2hwsw_version", "0.81.0"),
            "build_dir": py_params_dict.get("build_dir", ""),
            "py2hwsw_target": py_params_dict.get("py2hwsw_target", "setup"),
        }
    )

    # Use iob_memwrapper to wrap iob_system with MEM_ASIC=1
    attributes_dict = {
        "name": "iob_system_asic",
        "generate_hw": True,
        "confs": iob_system_attrs.get("confs", [])
        + [
            {
                "name": "MEM_ASIC",
                "type": "P",
                "val": "1",
                "min": "0",
                "max": "1",
                "descr": "Use ASIC hard macros (1) or behavioral RTL (0)",
            },
            {
                "name": "MEM_NO_READ_ON_WRITE",
                "type": "P",
                "val": "1",
                "min": "0",
                "max": "1",
                "descr": "No simultaneous read/write",
            },
        ],
        "ports": [
            {
                "name": "clk_en_rst_s",
                "descr": "Clock and reset",
                "signals": {
                    "type": "iob_clk",
                },
            },
        ],
        "subblocks": [
            {
                "core": "iob_memwrapper",
                "instance_name": "iob_system_mwrap",
                "instance_description": "Memory wrapper for ASIC flow (MEM_ASIC=1)",
                "parameters": {
                    "MEM_ASIC": 1,
                    "MEM_NO_READ_ON_WRITE": 1,
                },
                "connect": {
                    "clk_en_rst_s": "clk_en_rst_s",
                },
            },
        ],
    }

    # Generate ASIC config.json in the asic directory
    build_dir = py_params_dict.get("build_dir", "")
    if build_dir:
        asic_dir = os.path.join(build_dir, "hardware", "asic")
        os.makedirs(asic_dir, exist_ok=True)
        config_path = os.path.join(asic_dir, "config.json")

        # Generate config using asic_config_gen logic
        try:
            from asic_config_gen import get_default_config, write_config

            # Create a mock core object for config generation
            class MockCore:
                def __init__(self, name, build_dir, attrs, received_py_params):
                    self.name = name
                    self.build_dir = build_dir
                    self.attributes_dict = attrs
                    self.received_python_parameters = received_py_params

            mock_core = MockCore(
                "iob_system_asic",
                build_dir + "/hardware/asic",
                attributes_dict,
                py_params_dict,
            )
            config = get_default_config(mock_core, "sky130A", 20)
            write_config(config, asic_dir)
            print(f"{INFO} ASIC config.json generated at {config_path}{ENDC}")
        except Exception as e:
            print(f"{INFO} Could not generate ASIC config.json: {e}{ENDC}")

    print(
        f"{INFO} Generated iob_system_asic with memwrapper for ASIC flow (MEM_ASIC=1){ENDC}"
    )
    return attributes_dict
