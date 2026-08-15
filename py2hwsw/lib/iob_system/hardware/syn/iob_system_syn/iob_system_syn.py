# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: GPL-3.0-only


def setup(py_params_dict):
    params = py_params_dict["iob_system_params"]

    attributes_dict = {
        "name": params["name"] + "_syn",
        "generate_hw": True,
        "confs": [
            # empty for now
        ],
    }

    return attributes_dict
