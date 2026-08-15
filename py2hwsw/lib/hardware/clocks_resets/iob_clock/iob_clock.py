# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: GPL-3.0-only


def setup(py_params_dict):
    attributes_dict = {
        "generate_hw": True,
        "confs": [
            {
                "name": "CLK_PERIOD",
                "type": "P",
                "val": "10",
                "min": "",
                "max": "",
                "descr": "Clock period",
            },
        ],
        "ports": [
            {
                "name": "clk_o",
                "descr": "Output clock",
                "signals": [
                    {"name": "clk_o", "width": "1"},
                ],
            },
        ],
        "snippets": [
            {
                "verilog_code": """
   reg clk;
   assign clk_o = clk;
   initial clk = 0; always #(CLK_PERIOD/2) clk = ~clk;
        """,
            }
        ],
    }

    return attributes_dict
