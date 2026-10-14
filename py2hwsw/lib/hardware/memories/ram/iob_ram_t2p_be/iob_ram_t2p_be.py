# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: GPL-3.0-only


def setup(py_params_dict):
    attributes_dict = {
        "generate_hw": True,
        "confs": [
            {
                "name": "HEXFILE",
                "type": "P",
                "val": '"none"',
                "min": "NA",
                "max": "NA",
                "descr": "Name of file to load into RAM",
            },
            {
                "name": "ADDR_W",
                "type": "P",
                "val": "1",
                "min": "1",
                "max": "NA",
                "descr": "Address bus width",
            },
            {
                "name": "DATA_W",
                "type": "P",
                "val": "1",
                "min": "1",
                "max": "NA",
                "descr": "Data bus width",
            },
            {
                "name": "COL_W",
                "type": "D",
                "val": "8",
                "min": "NA",
                "max": "NA",
                "descr": "",
            },
            {
                "name": "NUM_COL",
                "type": "D",
                "val": "DATA_W / COL_W",
                "min": "NA",
                "max": "NA",
                "descr": "",
            },
            {
                "name": "MEM_ASIC",
                "type": "P",
                "val": "0",
                "min": "0",
                "max": "1",
                "descr": "Use ASIC hard macros (1) or behavioral RTL (0)",
            },
            {
                "name": "SIMULATION",
                "type": "P",
                "val": "1",
                "min": "0",
                "max": "1",
                "descr": "Use behavioral model for simulation (1) or sky130 macros (0)",
            },
        ],
        "ports": [
            {
                "name": "ram_t2p_be_s",
                "descr": "RAM interface",
                "signals": {
                    "type": "ram_t2p_be",
                    "ADDR_W": "ADDR_W",
                    "DATA_W": "DATA_W",
                },
            },
        ],
        "subblocks": [
            {
                "core": "iob_ram_t2p",
                "instantiate": False,
            },
        ],
        "snippets": [
            {
                "verilog_code": """
    generate
        if (MEM_ASIC && !SIMULATION) begin : g_asic
            // ASIC hard macro wrapper (sky130 1RW+1R SRAM with byte enable)
            // Map write port -> Port 0 (RW), read port -> Port 1 (R)
            // Declare the power nets here so they are not implicit wires. The
            // hard macro power pins are only connected by the wrapper when the
            // USE_POWER_PINS define is set (LibreLane enables it by default and
            // connects the macro power pins through the PDN/VDD_NETS).
            wire VPWR;
            wire VGND;
            sram_1rw1r_wrapper #(
                .ADDR_WIDTH(ADDR_W),
                .DATA_WIDTH(DATA_W),
                .SIMULATION(0)
            ) u_sram (
                .clk(clk_i),
                // Port 0 (RW): used for write operations with byte enable
                .csb0(~|w_strb_i),
                .web0(~|w_strb_i),
                .wmask0(w_strb_i),
                .addr0(w_addr_i),
                .din0(w_data_i),
                .dout0(/* open */),
                // Port 1 (R): used for read operations
                .csb1(~r_en_i),
                .addr1(r_addr_i),
                .dout1(r_data_o),
                .VPWR(VPWR),
                .VGND(VGND)
            );
        end else begin : g_behavioral
            genvar i;
            localparam file_suffix = {"7", "6", "5", "4", "3", "2", "1", "0"};
            for (i = 0; i < NUM_COL; i = i + 1) begin : ram_col
                localparam mem_init_file_int = (HEXFILE != "none") ?
                    {HEXFILE, "_", file_suffix[8*(i+1)-1-:8], ".hex"} : "none";

                iob_ram_t2p #(
                    .HEXFILE(mem_init_file_int),
                    .ADDR_W (ADDR_W),
                    .DATA_W (COL_W)
                ) ram (
                    .clk_i(clk_i),
                    .w_en_i  (w_strb_i[i]),
                    .w_addr_i(w_addr_i),
                    .w_data_i(w_data_i[i*COL_W+:COL_W]),
                    .r_en_i  (r_en_i),
                    .r_addr_i(r_addr_i),
                    .r_data_o(r_data_o[i*COL_W+:COL_W])
                );
            end
        end
    endgenerate
""",
            },
        ],
    }

    return attributes_dict
