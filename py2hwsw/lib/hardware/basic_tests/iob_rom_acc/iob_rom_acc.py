# SPDX-FileCopyrightText: 2025 IObundle
#
# SPDX-License-Identifier: MIT


def setup(py_params_dict):
    attributes_dict = {
        "name": "iob_rom_acc",
        "generate_hw": True,
        "confs": [
            {
                "name": "VALUES_DATA_W",
                "type": "P",
                "val": 8,
                "min": 1,
                "max": "NA",
                "descr": "Data width",
            },
            {
                "name": "VALUES_ADDR_W",
                "type": "P",
                "val": 4,
                "min": 1,
                "max": "NA",
                "descr": "Address width",
            },
            {
                "name": "VALUES_HEXFILE",
                "type": "P",
                "val": '"rom.hex"',
                "min": "NA",
                "max": "NA",
                "descr": "Hex file to load",
            },
        ],
        "ports": [
            {
                "name": "clk_en_rst_s",
                "wires": {"type": "iob_clk"},
                "descr": "Clock, enable and reset",
            },
            {
                "name": "start_i",
                "wires": [{"name": "start_i", "width": 1}],
                "descr": "Start wire",
            },
            {
                "name": "values_m",
                "wires": {
                    "type": "rom_sp",
                    "prefix": "values_",
                    "DATA_W": "VALUES_DATA_W",
                    "ADDR_W": "VALUES_ADDR_W",
                },
                "descr": "Memory interface",
            },
            {
                "name": "result_o",
                "wires": [{"name": "result_o", "width": "VALUES_DATA_W"}],
                "descr": "Result",
            },
        ],
        "buses": [
            {
                "name": "r_data_i",
                "wires": [{"name": "values_r_data_i"}],
            },
            {
                "name": "addr_o",
                "wires": [{"name": "values_addr_o"}],
            },
            {
                "name": "acc_en_rst",
                "wires": [
                    {"name": "acc_enable", "width": 1, "descr": "Enable wire"},
                    {
                        "name": "acc_reset",
                        "width": 1,
                        "descr": "Synchronous reset wire",
                    },
                ],
            },
            {
                "name": "ctr_en_rst",
                "wires": [
                    {"name": "ctr_enable", "width": 1, "descr": "Enable wire"},
                    {
                        "name": "ctr_reset",
                        "width": 1,
                        "descr": "Synchronous reset wire",
                    },
                ],
            },
        ],
        "subblocks": [
            {
                "core_name": "iob_acc",
                "instance_name": "accomulator0",
                "parameters": {
                    "DATA_W": "VALUES_DATA_W",
                    "RST_VAL": "{VALUES_DATA_W{1'b0}}",
                },
                "connect": {
                    "clk_en_rst_s": "clk_en_rst_s",
                    "en_rst_i": "acc_en_rst",
                    "incr_i": "r_data_i",
                    "data_o": "result_o",
                },
            },
            {
                "core_name": "iob_counter",
                "instance_name": "counter0",
                "parameters": {
                    "DATA_W": "VALUES_ADDR_W",
                    "RST_VAL": "{VALUES_ADDR_W{1'b0}}",
                },
                "connect": {
                    "clk_en_rst_s": "clk_en_rst_s",
                    "en_rst_i": "ctr_en_rst",
                    "data_o": "addr_o",
                },
            },
        ],
        "fsm": {
            "type": "fsm",
            "default_assignments": """
                ctr_enable = 1'b0;
                ctr_reset = 1'b0;
                acc_enable = 1'b0;
                acc_reset = 1'b0;
            """,
            "state_descriptions": """
            IDLE:
                if (start_i)
                begin
                    state_nxt = READ;
                    acc_reset = 1'b1;
                    ctr_reset = 1'b1;
                end

            READ:
                ctr_enable = 1'b1;
                state_nxt = ACCUMULATE;

            ACCUMULATE:
                acc_enable = 1'b1;
                if (values_addr_o == {VALUES_ADDR_W{1'b1}})
                    state_nxt = state + 1;
                else
                    state_nxt = READ;

            state_nxt = IDLE;
            """,
        },
        "snippets": [
            {
                "verilog_code": """
    assign values_clk_o = clk_i;
            """
            }
        ],
    }
    return attributes_dict
