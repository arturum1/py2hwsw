// SPDX-FileCopyrightText: 2026 IObundle
//
// SPDX-License-Identifier: GPL-3.0-only

// Wrapper for 1RW+1R SRAM macros (OpenRAM or PDK behavioral).
//
// SIMULATION=1  -> behavioral model (sim / lint / RTL)
// SIMULATION=0  -> includes `sram_1rw1r_macros.vh`, which is written
//                  by `openram-gen` (or kept as behavioral fallback
//                  when no OpenRAM macro is configured).

module sram_1rw1r_behavioral #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32
) (
    input  logic                    clk,
    // Port 0: RW
    input  logic                    csb0,
    input  logic                    web0,
    input  logic [DATA_WIDTH/8-1:0] wmask0,
    input  logic [ADDR_WIDTH-1:0]   addr0,
    input  logic [DATA_WIDTH-1:0]   din0,
    output logic [DATA_WIDTH-1:0]   dout0,
    // Port 1: R
    input  logic                    csb1,
    input  logic [ADDR_WIDTH-1:0]   addr1,
    output logic [DATA_WIDTH-1:0]   dout1
);
    localparam WMASK_W = DATA_WIDTH/8;
    logic [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

    always_ff @(posedge clk) begin
        if (!csb0 && !web0) begin
            for (int i = 0; i < DATA_WIDTH; i = i + 1) begin
                if (wmask0[(i/8) < WMASK_W ? (i/8) : WMASK_W-1])
                    mem[addr0][i] <= din0[i];
            end
        end
        if (!csb0 && web0) dout0 <= mem[addr0];
        if (!csb1)         dout1 <= mem[addr1];
    end
endmodule

module sram_1rw1r_wrapper #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32,
    parameter WRITE_SIZE = DATA_WIDTH,
    parameter SIMULATION = 1
) (
    input  logic                    clk,
    // Port 0: RW (byte-mask width is DATA_WIDTH/8 regardless; full-word writes pass all-1 mask)
    input  logic                    csb0,
    input  logic                    web0,
    input  logic [DATA_WIDTH/8-1:0] wmask0,
    input  logic [ADDR_WIDTH-1:0]   addr0,
    input  logic [DATA_WIDTH-1:0]   din0,
    output logic [DATA_WIDTH-1:0]   dout0,
    // Port 1: R
    input  logic                    csb1,
    input  logic [ADDR_WIDTH-1:0]   addr1,
    output logic [DATA_WIDTH-1:0]   dout1,
    // Power
    inout VPWR,
    inout VGND
);

    generate
        if (SIMULATION) begin : gen_sim
            sram_1rw1r_behavioral #(
                .ADDR_WIDTH (ADDR_WIDTH),
                .DATA_WIDTH (DATA_WIDTH)
            ) u_sram (
                .clk    (clk),
                .csb0   (csb0),
                .web0   (web0),
                .wmask0 (wmask0),
                .addr0  (addr0),
                .din0   (din0),
                .dout0  (dout0),
                .csb1   (csb1),
                .addr1  (addr1),
                .dout1  (dout1)
            );
        end else begin : gen_asic
            // The ASIC build writes the macro selection here.
            `include "sram_1rw1r_macros.vh"
        end
    endgenerate

endmodule
