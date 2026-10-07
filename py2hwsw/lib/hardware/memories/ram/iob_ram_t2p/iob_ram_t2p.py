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
                "name": "ram_t2p_s",
                "descr": "RAM interface",
                "signals": {
                    "type": "ram_t2p",
                    "ADDR_W": "ADDR_W",
                    "DATA_W": "DATA_W",
                },
            },
        ],
        "snippets": [
            {
                "verilog_code": """
    generate
        if (MEM_ASIC) begin : g_asic
            // ASIC hard macro wrapper (sky130 1RW+1R SRAM)
            // Map write port -> Port 0 (RW), read port -> Port 1 (R)
            sram_1rw1r_wrapper #(
                .ADDR_WIDTH(ADDR_W),
                .DATA_WIDTH(DATA_W)
            ) u_sram (
                .clk(clk_i),
                // Port 0 (RW): used for write operations
                .csb0(~w_en_i),
                .web0(~w_en_i),
                .wmask0({DATA_W/8{1'b1}}),
                .addr0(w_addr_i),
                .din0(w_data_i),
                .dout0(/* open */),
                // Port 1 (R): used for read operations
                .csb1(~r_en_i),
                .addr1(r_addr_i),
                .dout1(r_data_o),
                .VPWR(VPWR), .VGND(VGND)
            );
        end else begin : g_behavioral
            // Declare the RAM
            reg [DATA_W-1:0] mem    [(2**ADDR_W)-1:0];

            reg [DATA_W-1:0] r_data;
            // Initialize the RAM
            initial if (HEXFILE != "none") $readmemh(HEXFILE, mem, 0, (2 ** ADDR_W) - 1);

            //read port
            always @(posedge clk_i) begin
                if (r_en_i) begin
                    r_data <= mem[r_addr_i];
                end
            end

            //write port
            always @(posedge clk_i) begin
                if (w_en_i) begin
                    mem[w_addr_i] <= w_data_i;
                end
            end

            assign r_data_o = r_data;
        end
    endgenerate
            """,
            },
        ],
    }

    return attributes_dict
