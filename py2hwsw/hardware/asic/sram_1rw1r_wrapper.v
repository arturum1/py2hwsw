// SPDX-FileCopyrightText: 2026 IObundle
//
// SPDX-License-Identifier: GPL-3.0-only

// Parameterized wrapper for sky130 1RW+1R SRAM macros.
// Selects the appropriate macro based on address/data width.
// When SIMULATION=1, uses behavioral model (for Verilator lint/sim).
// When SIMULATION=0, instantiates sky130 hard macros.

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

    // Select macro based on address/data width
    // sky130 1RW+1R SRAM macros: 32-bit data width variants
    // 1KB: 256x32 (ADDR_WIDTH=8), 2KB: 512x32 (ADDR_WIDTH=9), 4KB: 1024x32 (ADDR_WIDTH=10)
    // 8KB: 2048x32 (ADDR_WIDTH=11), 16KB: 4096x32 (ADDR_WIDTH=12), 32KB: 8192x32 (ADDR_WIDTH=13)
    localparam MACRO_1KB_32  = "sky130_sram_1kbyte_1rw1r_32x256_8";
    localparam MACRO_2KB_32  = "sky130_sram_2kbyte_1rw1r_32x512_8";
    localparam MACRO_4KB_32  = "sky130_sram_4kbyte_1rw1r_32x1024_8";
    localparam MACRO_8KB_32  = "sky130_sram_8kbyte_1rw1r_32x2048_8";
    localparam MACRO_16KB_32 = "sky130_sram_16kbyte_1rw1r_32x4096_8";
    localparam MACRO_32KB_32 = "sky130_sram_32kbyte_1rw1r_32x8192_8";
    localparam MACRO_1KB_8   = "sky130_sram_1kbyte_1rw1r_8x1024_8";
    localparam MACRO_2KB_8   = "sky130_sram_2kbyte_1rw1r_8x2048_8";
    localparam MACRO_4KB_8   = "sky130_sram_4kbyte_1rw1r_8x4096_8";
    localparam MACRO_8KB_8   = "sky130_sram_8kbyte_1rw1r_8x8192_8";
    localparam MACRO_16KB_8  = "sky130_sram_16kbyte_1rw1r_8x16384_8";
    localparam MACRO_32KB_8  = "sky130_sram_32kbyte_1rw1r_8x32768_8";

    // Simulation: use behavioral model
    // Synthesis/ASIC flow: instantiate sky130 hard macros
    generate
        if (SIMULATION) begin : gen_sim
            // Behavioral fallback
            logic [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];
            
            always_ff @(posedge clk) begin
                if (!csb0 && !web0) begin
                    for (int i = 0; i < DATA_WIDTH/8; i++) begin
                        if (wmask0[i])
                            mem[addr0][i*8 +: 8] <= din0[i*8 +: 8];
                    end
                end
                if (!csb0 && !web0) dout0 <= 'x;
                else if (!csb0) dout0 <= mem[addr0];
                
                if (!csb1) dout1 <= mem[addr1];
                else dout1 <= 'x;
            end
        end else begin : gen_asic
            // Instantiate the appropriate sky130 macro using generate block
            if (DATA_WIDTH == 32) begin : gen_32bit
                if (ADDR_WIDTH <= 8) begin : g_1kb
                    sky130_sram_1kbyte_1rw1r_32x256_8 u_sram (
                    `ifdef USE_POWER_PINS
                        .vccd1(VPWR), .vssd1(VGND),
                    `endif
                        .clk0(clk), .csb0(csb0), .web0(web0), .wmask0(wmask0),
                        .addr0(addr0), .din0(din0), .dout0(dout0),
                        .clk1(clk), .csb1(csb1), .addr1(addr1), .dout1(dout1)
                    );
                end else if (ADDR_WIDTH <= 9) begin : g_2kb
                    sky130_sram_2kbyte_1rw1r_32x512_8 u_sram (
                    `ifdef USE_POWER_PINS
                        .vccd1(VPWR), .vssd1(VGND),
                    `endif
                        .clk0(clk), .csb0(csb0), .web0(web0), .wmask0(wmask0),
                        .addr0(addr0), .din0(din0), .dout0(dout0),
                        .clk1(clk), .csb1(csb1), .addr1(addr1), .dout1(dout1)
                    );
                end else if (ADDR_WIDTH <= 10) begin : g_4kb
                    sky130_sram_4kbyte_1rw1r_32x1024_8 u_sram (
                    `ifdef USE_POWER_PINS
                        .vccd1(VPWR), .vssd1(VGND),
                    `endif
                        .clk0(clk), .csb0(csb0), .web0(web0), .wmask0(wmask0),
                        .addr0(addr0), .din0(din0), .dout0(dout0),
                        .clk1(clk), .csb1(csb1), .addr1(addr1), .dout1(dout1)
                    );
                end else if (ADDR_WIDTH <= 11) begin : g_8kb
                    sky130_sram_8kbyte_1rw1r_32x2048_8 u_sram (
                    `ifdef USE_POWER_PINS
                        .vccd1(VPWR), .vssd1(VGND),
                    `endif
                        .clk0(clk), .csb0(csb0), .web0(web0), .wmask0(wmask0),
                        .addr0(addr0), .din0(din0), .dout0(dout0),
                        .clk1(clk), .csb1(csb1), .addr1(addr1), .dout1(dout1)
                    );
                end else if (ADDR_WIDTH <= 12) begin : g_16kb
                    sky130_sram_16kbyte_1rw1r_32x4096_8 u_sram (
                    `ifdef USE_POWER_PINS
                        .vccd1(VPWR), .vssd1(VGND),
                    `endif
                        .clk0(clk), .csb0(csb0), .web0(web0), .wmask0(wmask0),
                        .addr0(addr0), .din0(din0), .dout0(dout0),
                        .clk1(clk), .csb1(csb1), .addr1(addr1), .dout1(dout1)
                    );
                end else begin : g_32kb
                    sky130_sram_32kbyte_1rw1r_32x8192_8 u_sram (
                    `ifdef USE_POWER_PINS
                        .vccd1(VPWR), .vssd1(VGND),
                    `endif
                        .clk0(clk), .csb0(csb0), .web0(web0), .wmask0(wmask0),
                        .addr0(addr0), .din0(din0), .dout0(dout0),
                        .clk1(clk), .csb1(csb1), .addr1(addr1), .dout1(dout1)
                    );
                end
            end else begin : gen_8bit
                if (ADDR_WIDTH <= 8) begin : g_1kb
                    sky130_sram_1kbyte_1rw1r_8x1024_8 u_sram (
                    `ifdef USE_POWER_PINS
                        .vccd1(VPWR), .vssd1(VGND),
                    `endif
                        .clk0(clk), .csb0(csb0), .web0(web0), .wmask0(wmask0),
                        .addr0(addr0), .din0(din0), .dout0(dout0),
                        .clk1(clk), .csb1(csb1), .addr1(addr1), .dout1(dout1)
                    );
                end else if (ADDR_WIDTH <= 9) begin : g_2kb
                    sky130_sram_2kbyte_1rw1r_8x2048_8 u_sram (
                    `ifdef USE_POWER_PINS
                        .vccd1(VPWR), .vssd1(VGND),
                    `endif
                        .clk0(clk), .csb0(csb0), .web0(web0), .wmask0(wmask0),
                        .addr0(addr0), .din0(din0), .dout0(dout0),
                        .clk1(clk), .csb1(csb1), .addr1(addr1), .dout1(dout1)
                    );
                end else if (ADDR_WIDTH <= 10) begin : g_4kb
                    sky130_sram_4kbyte_1rw1r_8x4096_8 u_sram (
                    `ifdef USE_POWER_PINS
                        .vccd1(VPWR), .vssd1(VGND),
                    `endif
                        .clk0(clk), .csb0(csb0), .web0(web0), .wmask0(wmask0),
                        .addr0(addr0), .din0(din0), .dout0(dout0),
                        .clk1(clk), .csb1(csb1), .addr1(addr1), .dout1(dout1)
                    );
                end else if (ADDR_WIDTH <= 11) begin : g_8kb
                    sky130_sram_8kbyte_1rw1r_8x8192_8 u_sram (
                    `ifdef USE_POWER_PINS
                        .vccd1(VPWR), .vssd1(VGND),
                    `endif
                        .clk0(clk), .csb0(csb0), .web0(web0), .wmask0(wmask0),
                        .addr0(addr0), .din0(din0), .dout0(dout0),
                        .clk1(clk), .csb1(csb1), .addr1(addr1), .dout1(dout1)
                    );
                end else if (ADDR_WIDTH <= 12) begin : g_16kb
                    sky130_sram_16kbyte_1rw1r_8x16384_8 u_sram (
                    `ifdef USE_POWER_PINS
                        .vccd1(VPWR), .vssd1(VGND),
                    `endif
                        .clk0(clk), .csb0(csb0), .web0(web0), .wmask0(wmask0),
                        .addr0(addr0), .din0(din0), .dout0(dout0),
                        .clk1(clk), .csb1(csb1), .addr1(addr1), .dout1(dout1)
                    );
                end else begin : g_32kb
                    sky130_sram_32kbyte_1rw1r_8x32768_8 u_sram (
                    `ifdef USE_POWER_PINS
                        .vccd1(VPWR), .vssd1(VGND),
                    `endif
                        .clk0(clk), .csb0(csb0), .web0(web0), .wmask0(wmask0),
                        .addr0(addr0), .din0(din0), .dout0(dout0),
                        .clk1(clk), .csb1(csb1), .addr1(addr1), .dout1(dout1)
                    );
                end
            end
        end
    endgenerate

endmodule