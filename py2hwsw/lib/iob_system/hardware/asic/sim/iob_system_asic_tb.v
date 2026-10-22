// SPDX-FileCopyrightText: 2026 IObundle
//
// SPDX-License-Identifier: GPL-3.0-only

`timescale 1ns / 1ps

// Gate-level testbench for the ASIC implementation of iob_system.
//
// The netlist produced by the place-and-route flow is the flat netlist of the
// 'iob_system_asic' top module, so this testbench instantiates it directly.
// It is a smoke test: it checks that the outputs of the design are known
// after the reset is released, and that the design keeps running.

module iob_system_asic_tb;

   // Number of clock cycles of the smoke test
   localparam NUM_CYCLES = 100;
   // Clock period (ns)
   localparam PER = 10;

   integer fd;
   integer i;
   integer errors = 0;

   reg clk;
   reg cke;
   reg arst;
   reg rs232_rxd;
   reg rs232_cts;

   wire rs232_txd;
   wire rs232_rts;

   initial clk = 0;
   always #(PER / 2) clk = ~clk;

   // The outputs of the design must never be unknown
   always @(posedge clk) begin
      if (cke && !arst) begin
         if (rs232_txd === 1'bx) begin
            $display("ERROR: 'rs232_txd_o' is unknown");
            errors = errors + 1;
         end
         if (rs232_rts === 1'bx) begin
            $display("ERROR: 'rs232_rts_o' is unknown");
            errors = errors + 1;
         end
      end
   end

   initial begin
`ifdef VCD
      $dumpfile("uut.vcd");
      $dumpvars();
`endif
      cke       = 1;
      arst      = 1;
      rs232_rxd = 1;
      rs232_cts = 1;

      // Hold the reset for a few cycles
      repeat (5) @(posedge clk);
      @(negedge clk);
      arst = 0;

      // Let the design run
      for (i = 0; i < NUM_CYCLES; i = i + 1)
        @(posedge clk);

      if (errors == 0) begin
         $display("Test completed successfully.");
         fd = $fopen("test.log", "w");
         $fdisplay(fd, "Test passed!");
         $fclose(fd);
      end else begin
         $display("Test failed: %d unknown value(s) on the outputs.", errors);
         fd = $fopen("test.log", "w");
         $fdisplay(fd, "Test failed: %d unknown value(s) on the outputs.", errors);
         $fclose(fd);
      end

      $finish();
   end

   // The design under test: the top module of the ASIC implementation
   iob_system_asic uut (
      .clk_i       (clk),
      .cke_i       (cke),
      .arst_i      (arst),
      .rs232_rxd_i (rs232_rxd),
      .rs232_txd_o (rs232_txd),
      .rs232_rts_o (rs232_rts),
      .rs232_cts_i (rs232_cts)
   );

endmodule
