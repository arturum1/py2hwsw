// SPDX-FileCopyrightText: 2026 IObundle
//
// SPDX-License-Identifier: GPL-3.0-only

// Wrapper for ROM macros (OpenRAM or behavioral).
// SIMULATION=1 -> behavioral model with $readmemh
// SIMULATION=0 -> includes `rom_1rw_macros.vh`

module rom_1rw_behavioral #(
    parameter ADDR_WIDTH = 10,
    parameter DATA_WIDTH = 32,
    parameter HEXFILE = "none"
) (
    input  logic                    clk,
    input  logic                    en,
    input  logic [ADDR_WIDTH-1:0] addr,
    output logic [DATA_WIDTH-1:0] dout
);
    localparam INIT_RAM = (HEXFILE != "none" && HEXFILE != "none.hex") ? 1 : 0;
    reg [DATA_WIDTH-1:0] rom [0:(1<<ADDR_WIDTH)-1];
    reg [DATA_WIDTH-1:0] r_data_int;
    initial if (INIT_RAM) $readmemh(HEXFILE, rom, 0, (2**ADDR_WIDTH)-1);
    always @(posedge clk) begin
        if (en) r_data_int <= rom[addr];
    end
    assign dout = r_data_int;
endmodule

module rom_1rw_wrapper #(
    parameter ADDR_WIDTH = 10,
    parameter DATA_WIDTH = 32,
    parameter HEXFILE = "none",
    parameter SIMULATION = 1
) (
    input  logic                    clk,
    input  logic                    en,
    input  logic [ADDR_WIDTH-1:0] addr,
    output logic [DATA_WIDTH-1:0] dout,
    inout VPWR,
    inout VGND
);
    generate
        if (SIMULATION) begin : gen_sim
            rom_1rw_behavioral #(
                .ADDR_WIDTH (ADDR_WIDTH),
                .DATA_WIDTH (DATA_WIDTH),
                .HEXFILE (HEXFILE)
            ) u_rom (
                .clk  (clk),
                .en   (en),
                .addr (addr),
                .dout (dout)
            );
        end else begin : gen_asic
            `include "rom_1rw_macros.vh"
        end
    endgenerate
endmodule
