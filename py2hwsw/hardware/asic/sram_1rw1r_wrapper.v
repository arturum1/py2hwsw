// SPDX-FileCopyrightText: 2026 IObundle
//
// SPDX-License-Identifier: GPL-3.0-only

// Parameterized wrapper for sky130 1RW+1R SRAM macros.
//
// The hard macro is only used when its geometry matches the requested one
// exactly, because the address and data widths of the macro ports are fixed.
// Memories with any other geometry are implemented with a behavioral model,
// which the synthesis flow maps to standard cells.
//
// Keep the list of macros in sync with 'SKY130_MACROS' in
// 'py2hwsw/scripts/asic_config_gen.py', which adds the views (GDSII, LEF and
// Verilog model) of the macros to the configuration of the ASIC flow.

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

    // Number of byte write enables
    localparam WMASK_W = DATA_WIDTH/8;

    logic [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

    always_ff @(posedge clk) begin
        // Write port (port 0)
        if (!csb0 && !web0) begin
            for (int i = 0; i < DATA_WIDTH; i = i + 1) begin
                // The bits of a word whose width is not a multiple of 8 are
                // masked by the last byte enable, which is the most precise
                // granularity available
                if (wmask0[(i/8) < WMASK_W ? (i/8) : WMASK_W-1])
                    mem[addr0][i] <= din0[i];
            end
        end
        // Read ports
        if (!csb0 && web0) dout0 <= mem[addr0];
        if (!csb1)         dout1 <= mem[addr1];
    end

endmodule

module sram_1rw1r_wrapper #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32,
    parameter SIMULATION = 1
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
            // The sky130 1RW+1R SRAM macros of the PDK, with their geometry:
            //   sky130_sram_1kbyte_1rw1r_32x256_8: 256 words of 32 bits
            //   sky130_sram_2kbyte_1rw1r_32x512_8: 512 words of 32 bits
            //   sky130_sram_1kbyte_1rw1r_8x1024_8: 1024 words of 8 bits
            if ((ADDR_WIDTH == 8) && (DATA_WIDTH == 32)) begin : g_1kbyte_32x256
                sky130_sram_1kbyte_1rw1r_32x256_8 u_sram (
                `ifdef USE_POWER_PINS
                    .vccd1(VPWR), .vssd1(VGND),
                `endif
                    .clk0(clk), .csb0(csb0), .web0(web0), .wmask0(wmask0),
                    .addr0(addr0), .din0(din0), .dout0(dout0),
                    .clk1(clk), .csb1(csb1), .addr1(addr1), .dout1(dout1)
                );
            end else if ((ADDR_WIDTH == 9) && (DATA_WIDTH == 32)) begin : g_2kbyte_32x512
                sky130_sram_2kbyte_1rw1r_32x512_8 u_sram (
                `ifdef USE_POWER_PINS
                    .vccd1(VPWR), .vssd1(VGND),
                `endif
                    .clk0(clk), .csb0(csb0), .web0(web0), .wmask0(wmask0),
                    .addr0(addr0), .din0(din0), .dout0(dout0),
                    .clk1(clk), .csb1(csb1), .addr1(addr1), .dout1(dout1)
                );
            end else if ((ADDR_WIDTH == 10) && (DATA_WIDTH == 8)) begin : g_1kbyte_8x1024
                sky130_sram_1kbyte_1rw1r_8x1024_8 u_sram (
                `ifdef USE_POWER_PINS
                    .vccd1(VPWR), .vssd1(VGND),
                `endif
                    .clk0(clk), .csb0(csb0), .web0(web0), .wmask0(wmask0),
                    .addr0(addr0), .din0(din0), .dout0(dout0),
                    .clk1(clk), .csb1(csb1), .addr1(addr1), .dout1(dout1)
                );
            end else begin : g_behavioral
                // No macro with this geometry is available
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
            end
        end
    endgenerate

endmodule
