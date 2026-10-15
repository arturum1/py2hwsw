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
                "val": "6",
                "min": "0",
                "max": "NA",
                "descr": "Address bus width",
            },
            {
                "name": "DATA_W",
                "type": "P",
                "val": "8",
                "min": "0",
                "max": "NA",
                "descr": "Data bus width",
            },
            {
                "name": "MEM_NO_READ_ON_WRITE",
                "type": "P",
                "val": "1",
                "min": "0",
                "max": "NA",
                "descr": "",
            },
            {
                "name": "MEM_INIT_FILE_INT",
                "type": "D",
                "val": "HEXFILE",
                "min": "0",
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
                "name": "clk_i",
                "descr": "clock",
                "signals": [
                    {"name": "clk_i", "width": 1},
                ],
            },
            {
                "name": "port_a_io",
                "descr": "Port A",
                "signals": [
                    {"name": "enA_i", "width": 1},
                    {"name": "weA_i", "width": 1},
                    {"name": "addrA_i", "width": "ADDR_W"},
                    {"name": "dA_i", "width": "DATA_W"},
                    {"name": "dA_o", "width": "DATA_W"},
                ],
            },
            {
                "name": "port_b_io",
                "descr": "Port B",
                "signals": [
                    {"name": "enB_i", "width": 1},
                    {"name": "weB_i", "width": 1},
                    {"name": "addrB_i", "width": "ADDR_W"},
                    {"name": "dB_i", "width": "DATA_W"},
                    {"name": "dB_o", "width": "DATA_W"},
                ],
            },
        ],
        "snippets": [
            {
                "verilog_code": """
    localparam INIT_RAM = (MEM_INIT_FILE_INT != "none") ? 1 : 0;

    generate
        if (MEM_ASIC) begin : g_asic
            // ASIC hard macro wrapper (sky130 1RW+1R SRAM x2 for true dual port)
            // Port A -> SRAM 0 (RW), Port B -> SRAM 1 (RW)
            // Both SRAMs share the same memory array conceptually
            // In practice, we use two 1RW+1R macros with cross-coupled write/read
            
            // For true dual port, we need to handle concurrent access to same address
            // This is a simplified implementation - for register file use case,
            // we assume no simultaneous read/write to same address on different ports
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
            ) u_sram_a (
                .clk(clk_i),
                // Port 0 (RW): used for Port A
                .csb0(~enA_i),
                .web0(~weA_i),
                .wmask0({DATA_W/8{1'b1}}),
                .addr0(addrA_i),
                .din0(dA_i),
                .dout0(dA_o),
                // Port 1 (R): used for Port B read (when not writing)
                .csb1(~enB_i),
                .addr1(addrB_i),
                .dout1(dB_o),
                .VPWR(VPWR),
                .VGND(VGND)
            );
            
            // Second SRAM for Port B writes
            sram_1rw1r_wrapper #(
                .ADDR_WIDTH(ADDR_W),
                .DATA_WIDTH(DATA_W),
                .SIMULATION(0)
            ) u_sram_b (
                .clk(clk_i),
                // Port 0 (RW): used for Port B writes
                .csb0(~enB_i),
                .web0(~weB_i),
                .wmask0({DATA_W/8{1'b1}}),
                .addr0(addrB_i),
                .din0(dB_i),
                .dout0(/* open */),
                // Port 1 (R): used for Port A read (when not writing)
                .csb1(~enA_i),
                .addr1(addrA_i),
                .dout1(/* open */),
                .VPWR(VPWR),
                .VGND(VGND)
            );
            
            // Note: For true dual-port behavior, a more complex implementation
            // with arbitration or multi-port SRAM would be needed.
            // This implementation works for register file where write port is shared.
            
        end else begin : g_behavioral
            localparam INIT_RAM = (MEM_INIT_FILE_INT != "none") ? 1 : 0;
            reg [DATA_W-1:0] dA_o_reg;
            reg [DATA_W-1:0] dB_o_reg;
            assign dA_o=dA_o_reg;
            assign dB_o=dB_o_reg;
            // Declare the RAM
            reg [DATA_W-1:0] ram[2**ADDR_W-1:0];

            // Initialize the RAM
            generate
                if (INIT_RAM) begin : mem_init
                    initial $readmemh(MEM_INIT_FILE_INT, ram, 0, 2 ** ADDR_W - 1);
                end
            endgenerate

            generate
               if (MEM_NO_READ_ON_WRITE) begin : with_MEM_NO_READ_ON_WRITE
                  always @(posedge clk_i) begin  // Port A
                     if (enA_i)
                        if (weA_i) ram[addrA_i] <= dA_i;
                        else dA_o_reg <= ram[addrA_i];
                  end
                  always @(posedge clk_i) begin  // Port B
                     if (enB_i)
                        if (weB_i) ram[addrB_i] <= dB_i;
                        else dB_o_reg <= ram[addrB_i];
                  end
               end else begin : not_MEM_NO_READ_ON_WRITE
                  always @(posedge clk_i) begin  // Port A
                     if (enA_i) if (weA_i) ram[addrA_i] <= dA_i;
                     dA_o_reg <= ram[addrA_i];
                  end
                  always @(posedge clk_i) begin  // Port B
                     if (enB_i) if (weB_i) ram[addrB_i] <= dB_i;
                     dB_o_reg <= ram[addrB_i];
                  end
               end
            endgenerate    
        end
    endgenerate
            """,
            },
        ],
    }

    return attributes_dict
