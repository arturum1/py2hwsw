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
                "val": "10",
                "min": "0",
                "max": "NA",
                "descr": "Address bus width",
            },
            {
                "name": "DATA_W",
                "type": "P",
                "val": "32",
                "min": "0",
                "max": "NA",
                "descr": "Data bus width",
            },
            {
                "name": "MEM_INIT_FILE_INT",
                "type": "D",
                "val": '{HEXFILE, ".hex"}',
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
        ],
        "ports": [
            {
                "name": "rom_sp_s",
                "descr": "ROM interface",
                "signals": {
                    "type": "rom_sp",
                    "ADDR_W": "ADDR_W",
                    "DATA_W": "DATA_W",
                },
            },
        ],
        "snippets": [
            {
                "verilog_code": """
    localparam INIT_RAM = (MEM_INIT_FILE_INT != "none.hex") ? 1 : 0;

    generate
        if (MEM_ASIC) begin : g_asic
            // ASIC hard macro wrapper (sky130 SRAM 1RW+1R with write port tied off)
            bootrom_wrapper #(
                .ADDR_W(ADDR_W),
                .DATA_W(DATA_W),
                .HEXFILE(MEM_INIT_FILE_INT),
                .SIMULATION(0)
            ) u_bootrom (
                .clk(clk_i),
                .addr(addr_i),
                .data(r_data_o),
                .VPWR(VPWR), .VGND(VGND)
            );
        end else begin : g_behavioral
            // Declare the ROM
            reg [DATA_W-1:0] rom[(2**ADDR_W)-1:0];
            reg [DATA_W-1:0] r_data_int;

            // Initialize the ROM
            initial if (INIT_RAM) $readmemh( MEM_INIT_FILE_INT, rom, 0, (2 ** ADDR_W) - 1);

            // Operate the ROM
            always @(posedge clk_i) if (en_i)
            r_data_int <= rom[addr_i];

            assign r_data_o = r_data_int;
        end
    endgenerate
             """,
            },
        ],
    }

    return attributes_dict
