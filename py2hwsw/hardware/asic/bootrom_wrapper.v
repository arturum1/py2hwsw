// SPDX-FileCopyrightText: 2026 IObundle
//
// SPDX-License-Identifier: GPL-3.0-only

// Bootrom wrapper for ASIC flow.
// Uses sram_1rw1r_wrapper (which instantiates sky130 1RW+1R SRAM) with write port tied off.
// When SIMULATION=1, uses behavioral model (for Verilator lint/sim).
// When SIMULATION=0, instantiates sram_1rw1r_wrapper with write port tied off.

module bootrom_wrapper #(
    parameter ADDR_W = 10,
    parameter DATA_W = 32,
    parameter HEXFILE = "bootrom.hex",
    parameter SIMULATION = 1
) (
    input  logic                    clk,
    input  logic [ADDR_W-1:0]       addr,
    output logic [DATA_W-1:0]       data,
    inout VPWR,
    inout VGND
);

    // Simulation: use behavioral model
    // Synthesis/ASIC flow: instantiate sram_1rw1r_wrapper with write port tied off
    generate
        if (SIMULATION) begin : gen_sim
            // Behavioral model for simulation/Verilator lint
            logic [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];
            
            always_ff @(posedge clk) begin
                data <= mem[addr];
            end
            
            // Initialize from hex file at synthesis time
            initial $readmemh(HEXFILE, mem);
            
        end else begin : gen_asic
            // Instantiate sram_1rw1r_wrapper with write port tied off
            // sram_1rw1r_wrapper has two ports:
            // Port 0 (RW): clk, csb0, web0, wmask0, addr0, din0, dout0
            // Port 1 (R):  clk, csb1, addr1, dout1
            // For bootrom: tie off Port 0 (write), use Port 1 for reading
            sram_1rw1r_wrapper #(
                .ADDR_WIDTH(ADDR_W),
                .DATA_WIDTH(DATA_W),
                .SIMULATION(0)
            ) u_sram (
                .clk(clk),
                // Port 0 (RW) - tied off for bootrom (read-only)
                .csb0(1'b0),
                .web0(1'b1),
                .wmask0({DATA_W/8{1'b0}}),
                .addr0(addr),
                .din0({DATA_W{1'b0}}),
                .dout0(/* open */),
                // Port 1 (R) - used for bootrom read
                .csb1(~1'b1),  // active low, so 0 = enabled
                .addr1(addr),
                .dout1(data),
                .VPWR(VPWR),
                .VGND(VGND)
            );
        end
    endgenerate

endmodule